import {
  adminClient,
  authenticatedUser,
  corsHeaders,
  response,
} from '../_shared/core.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const user = await authenticatedUser(req)
    const body = await req.json().catch(() => ({}))
    const code = String(body.code ?? '').trim().toUpperCase()
    const psid = String(body.psid ?? `TEST-PSID-${code}`).trim()
    const messageText = String(body.message ?? `Hola, mi código es ${code}`)
    if (!/^[A-Z0-9]{6}$/.test(code)) {
      return response({ error: 'Código inválido. Usa 6 caracteres.' }, 400)
    }
    const client = adminClient()
    const { data: page } = await client
      .from('facebook_pages')
      .select()
      .eq('owner_id', user.id)
      .eq('is_selected', true)
      .single()
    if (!page) return response({ error: 'No hay página seleccionada' }, 400)

    let { data: identity } = await client
      .from('customer_meta_identities')
      .select('*, customers(*)')
      .eq('page_id', page.id)
      .eq('confirmation_code', code)
      .maybeSingle()
    if (!identity) return response({ error: 'Código no encontrado' }, 404)

    const eligibleUntil = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
    await client
      .from('customer_meta_identities')
      .update({ messenger_psid: psid, messenger_eligible_until: eligibleUntil })
      .eq('id', identity.id)
    await client
      .from('customers')
      .update({ is_provisional: false })
      .eq('id', identity.customer_id)
    identity = { ...identity, messenger_psid: psid }

    const { data: conversation, error: conversationError } = await client
      .from('conversations')
      .upsert({
        owner_id: user.id,
        page_id: page.id,
        customer_id: identity.customer_id,
        messenger_psid: psid,
        last_message_at: new Date().toISOString(),
        can_message_until: eligibleUntil,
        unread_count: 1,
      }, { onConflict: 'page_id,messenger_psid' })
      .select()
      .single()
    if (conversationError) throw conversationError

    const metaMessageId = `test-${crypto.randomUUID()}`
    await client.from('messages').insert({
      conversation_id: conversation.id,
      meta_message_id: metaMessageId,
      direction: 'incoming',
      body: messageText,
      status: 'received',
      meta_created_at: new Date().toISOString(),
    })

    const { data: batches } = await client
      .from('winner_notification_batches')
      .update({
        conversation_id: conversation.id,
        messenger_psid: psid,
        status: 'pending',
        last_error: null,
      })
      .eq('customer_id', identity.customer_id)
      .eq('confirmation_code', code)
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

    return response({
      ok: true,
      conversation_id: conversation.id,
      customer_id: identity.customer_id,
      batches: batches?.length ?? 0,
    })
  } catch (error) {
    if (error instanceof Response) return error
    return response({ error: error.message ?? String(error) }, 500)
  }
})
