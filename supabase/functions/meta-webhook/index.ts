import { adminClient, corsHeaders, response } from '../_shared/core.ts'

function hex(bytes: Uint8Array) { return [...bytes].map((value) => value.toString(16).padStart(2, '0')).join('') }

async function validSignature(raw: string, signature: string | null) {
  const secret = Deno.env.get('META_APP_SECRET')
  if (!secret || !signature?.startsWith('sha256=')) return false
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const expected = `sha256=${hex(new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(raw))))}`
  if (expected.length !== signature.length) return false
  let difference = 0
  for (let index = 0; index < expected.length; index++) difference |= expected.charCodeAt(index) ^ signature.charCodeAt(index)
  return difference === 0
}

async function eventId(payload: unknown) {
  return hex(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(payload)))))
}

function validAmount(message: string) {
  const match = message.match(/^\s*\$?\s*([0-9]+)\s*$/)
  if (!match) return null
  const amount = Number(match[1])
  return Number.isSafeInteger(amount) ? amount : null
}

async function processFeedChange(client: ReturnType<typeof adminClient>, pageId: string, change: Record<string, any>) {
  if (change.field !== 'feed' || change.value?.item !== 'comment' || change.value?.verb !== 'add') return
  const value = change.value
  const rawIds = [value.parent_id, value.post_id].filter(Boolean).map(String)
  const photoIds = [...new Set(rawIds.flatMap((id) => [id, id.split('_').at(-1)!]))]
  const { data: item } = await client.from('publication_items')
    .select('*, publications(*)')
    .in('meta_photo_id', photoIds)
    .maybeSingle()
  if (!item?.publications || item.publications.page_id !== pageId) return
  const publication = item.publications
  const created = typeof value.created_time === 'number'
    ? new Date(value.created_time * 1000)
    : new Date(value.created_time ?? Date.now())
  const amount = validAmount(String(value.message ?? ''))
  const beforeClose = created.getTime() < new Date(publication.ends_at).getTime()
  const onGrid = amount !== null && amount >= publication.starting_bid && (amount - publication.starting_bid) % publication.bid_increment === 0
  const valid = amount !== null && beforeClose && onGrid
  const rejection = amount === null ? 'format' : !beforeClose ? 'after_close' : !onGrid ? 'minimum_bid' : null
  const { data: comment, error } = await client.from('meta_comments').upsert({
    publication_item_id: item.id,
    meta_comment_id: String(value.comment_id),
    author_meta_id: value.from?.id ? String(value.from.id) : null,
    author_name: value.from?.name,
    message: String(value.message ?? ''),
    meta_created_at: created.toISOString(),
    raw_payload: value,
  }, { onConflict: 'meta_comment_id' }).select().single()
  if (error) throw error
  if (amount !== null) {
    await client.from('bids').upsert({
      comment_id: comment.id,
      publication_item_id: item.id,
      amount,
      meta_created_at: created.toISOString(),
      is_valid: valid,
      rejection_reason: rejection,
    }, { onConflict: 'comment_id' })
  }
  const { data: highest } = await client.from('bids')
    .select('comment_id,amount')
    .eq('publication_item_id', item.id)
    .eq('is_valid', true)
    .order('amount', { ascending: false })
    .order('meta_created_at', { ascending: true })
    .limit(1)
    .maybeSingle()
  await client.from('publication_items').update({
    winning_comment_id: highest?.comment_id ?? null,
    winning_amount: highest?.amount ?? null,
  }).eq('id', item.id)
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method === 'GET') {
    const url = new URL(req.url)
    if (url.searchParams.get('hub.mode') === 'subscribe' && url.searchParams.get('hub.verify_token') === Deno.env.get('META_WEBHOOK_VERIFY_TOKEN')) return new Response(url.searchParams.get('hub.challenge') ?? '', { status: 200 })
    return new Response('Verificación rechazada', { status: 403 })
  }
  const raw = await req.text()
  if (!await validSignature(raw, req.headers.get('x-hub-signature-256'))) return response({ error: 'Firma inválida' }, 401)
  const payload = JSON.parse(raw)
  const client = adminClient()
  const id = await eventId(payload)
  const { data: recorded } = await client.rpc('service_record_webhook_event', { event_id: id, target_event_type: payload.object ?? 'unknown', target_payload: payload })
  if (!recorded) return response({ received: true, duplicate: true })
  try {
    for (const entry of payload.entry ?? []) {
      const { data: page } = await client.from('facebook_pages').select().eq('meta_page_id', String(entry.id)).maybeSingle()
      if (!page) continue
      for (const change of entry.changes ?? []) await processFeedChange(client, page.id, change)
      for (const event of entry.messaging ?? []) {
        if (!event.message || event.message.is_echo) continue
        const psid = String(event.sender.id)
        const text = String(event.message.text ?? '')
        let { data: identity } = await client.from('customer_meta_identities').select('*, customers(*)').eq('page_id', page.id).eq('messenger_psid', psid).maybeSingle()
        if (!identity) {
          const codes = text.toUpperCase().match(/[A-Z0-9]{6}/g) ?? []
          if (codes.length) {
            const { data: byCode } = await client.from('customer_meta_identities').select('*, customers(*)').eq('page_id', page.id).in('confirmation_code', codes).maybeSingle()
            if (byCode) {
              await client.from('customer_meta_identities').update({ messenger_psid: psid, messenger_eligible_until: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString() }).eq('id', byCode.id)
              await client.from('customers').update({ is_provisional: false }).eq('id', byCode.customer_id)
              identity = byCode
            }
          }
        }
        let customer = identity?.customers
        if (!customer) {
          const { data } = await client.from('customers').insert({ owner_id: page.owner_id, page_id: page.id, display_name: 'Cliente de Messenger', is_provisional: true }).select().single()
          customer = data
          const { data: createdIdentity } = await client.from('customer_meta_identities').insert({ customer_id: customer.id, page_id: page.id, messenger_psid: psid, messenger_eligible_until: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString() }).select().single()
          identity = createdIdentity
        } else {
          await client.from('customer_meta_identities').update({ messenger_eligible_until: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString() }).eq('id', identity.id)
        }
        const sentAt = new Date(Number(event.timestamp ?? Date.now())).toISOString()
        const { data: conversation } = await client.from('conversations').upsert({ owner_id: page.owner_id, page_id: page.id, customer_id: customer.id, messenger_psid: psid, last_message_at: sentAt, can_message_until: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString() }, { onConflict: 'page_id,messenger_psid' }).select().single()
        await client.from('messages').upsert({ conversation_id: conversation.id, meta_message_id: event.message.mid, direction: 'incoming', body: text, status: 'received', meta_created_at: sentAt }, { onConflict: 'meta_message_id' })
        await client.from('conversations').update({ unread_count: conversation.unread_count + 1 }).eq('id', conversation.id)
        const codes = text.toUpperCase().match(/[A-Z0-9]{6}/g) ?? []
        if (identity?.customer_id && codes.length) {
          const { data: batches } = await client.from('winner_notification_batches')
            .update({
              conversation_id: conversation.id,
              messenger_psid: psid,
              status: 'pending',
              last_error: null,
            })
            .eq('customer_id', identity.customer_id)
            .in('confirmation_code', codes)
            .in('status', ['skipped', 'failed', 'pending'])
            .select('id,owner_id')
          for (const batch of batches ?? []) {
            await client.from('automation_jobs').upsert({
              owner_id: batch.owner_id,
              kind: 'winner_notification',
              entity_id: batch.id,
              run_at: new Date().toISOString(),
              status: 'pending',
              attempts: 0,
              idempotency_key: `winner-notification:${batch.id}`,
              last_error: null,
            }, { onConflict: 'idempotency_key' })
          }
        }
      }
    }
    await client.rpc('service_complete_webhook_event', { event_id: id, target_error: null })
    return response({ received: true })
  } catch (error) {
    await client.rpc('service_complete_webhook_event', { event_id: id, target_error: error.message ?? String(error) })
    return response({ received: true, processing_error: error.message ?? String(error) })
  }
})
