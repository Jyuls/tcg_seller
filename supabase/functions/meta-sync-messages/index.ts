import {
  adminClient,
  authenticatedUser,
  corsHeaders,
  graph,
  pageToken,
  response,
  verifyCron,
} from '../_shared/core.ts'

function pagePathFromUrl(url: string) {
  return url.replace(/^https:\/\/graph\.facebook\.com\/v[0-9.]+\//, '')
}

async function graphPages(path: string, token: string, maxPages = 10) {
  const rows: Record<string, any>[] = []
  let nextPath = path
  for (let page = 0; nextPath && page < maxPages; page++) {
    const payload = await graph(nextPath, token)
    rows.push(...(payload.data ?? []))
    nextPath = payload.paging?.next ? pagePathFromUrl(payload.paging.next) : ''
  }
  return rows
}

function participantForCustomer(
  participants: Record<string, any>[],
  pageMetaId: string,
) {
  return participants.find((participant) => String(participant.id) !== pageMetaId)
}

function newestIncoming(messages: Record<string, any>[], pageMetaId: string) {
  const incoming = messages
    .filter((message) => String(message.from?.id ?? '') !== pageMetaId)
    .map((message) => new Date(message.created_time as string))
    .filter((date) => !Number.isNaN(date.getTime()))
    .sort((a, b) => b.getTime() - a.getTime())
  return incoming[0] ?? null
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const client = adminClient()
    const cron = await verifyCron(req, client)
    const user = cron ? null : await authenticatedUser(req)
    let pagesQuery = client
      .from('facebook_pages')
      .select()
      .eq('is_selected', true)
      .eq('access_status', 'active')
    if (user) pagesQuery = pagesQuery.eq('owner_id', user.id)
    const { data: pages } = await pagesQuery
    let syncedConversations = 0
    let syncedMessages = 0

    for (const page of pages ?? []) {
      const token = await pageToken(client, page.id)
      const conversations = await graphPages(
        `${page.meta_page_id}/conversations?fields=id,updated_time,participants,messages.limit(50){id,message,from,to,created_time,attachments}&limit=50`,
        token,
        10,
      )
      for (const thread of conversations) {
        const participants = thread.participants?.data ?? []
        const customerParticipant = participantForCustomer(
          participants,
          page.meta_page_id,
        )
        const psid = customerParticipant?.id ? String(customerParticipant.id) : null
        if (!psid) continue
        const displayName = customerParticipant?.name
          ? String(customerParticipant.name)
          : 'Cliente de Messenger'
        const messages = thread.messages?.data ?? []
        const lastIncoming = newestIncoming(messages, page.meta_page_id)
        const canMessageUntil = lastIncoming
          ? new Date(lastIncoming.getTime() + 24 * 60 * 60 * 1000).toISOString()
          : null
        let { data: identity } = await client
          .from('customer_meta_identities')
          .select('*, customers(*)')
          .eq('page_id', page.id)
          .eq('messenger_psid', psid)
          .maybeSingle()
        if (!identity) {
          const { data: customer, error: customerError } = await client
            .from('customers')
            .insert({
              owner_id: page.owner_id,
              page_id: page.id,
              display_name: displayName,
              is_provisional: false,
            })
            .select()
            .single()
          if (customerError) throw customerError
          const { data: createdIdentity, error: identityError } = await client
            .from('customer_meta_identities')
            .insert({
              customer_id: customer.id,
              page_id: page.id,
              messenger_psid: psid,
              messenger_eligible_until: canMessageUntil,
            })
            .select('*, customers(*)')
            .single()
          if (identityError) throw identityError
          identity = createdIdentity
        } else {
          await client
            .from('customer_meta_identities')
            .update({ messenger_eligible_until: canMessageUntil })
            .eq('id', identity.id)
          if (
            identity.customers?.display_name === 'Cliente de Messenger' &&
            displayName !== 'Cliente de Messenger'
          ) {
            await client
              .from('customers')
              .update({ display_name: displayName, is_provisional: false })
              .eq('id', identity.customer_id)
          }
        }

        const newestMessageAt = messages
          .map((message: Record<string, any>) => new Date(message.created_time))
          .filter((date: Date) => !Number.isNaN(date.getTime()))
          .sort((a: Date, b: Date) => b.getTime() - a.getTime())[0]
        const { data: conversation, error: conversationError } = await client
          .from('conversations')
            .upsert({
            owner_id: page.owner_id,
            page_id: page.id,
            customer_id: identity.customer_id,
            messenger_psid: psid,
            last_message_at:
              newestMessageAt?.toISOString() ??
              thread.updated_time ??
              new Date().toISOString(),
            can_message_until: canMessageUntil,
          }, { onConflict: 'page_id,messenger_psid' })
          .select()
          .single()
        if (conversationError) throw conversationError
        syncedConversations++

        for (const message of messages) {
          const direction =
            String(message.from?.id ?? '') === page.meta_page_id
              ? 'outgoing'
              : 'incoming'
          const body = String(message.message ?? '').trim() ||
            (message.attachments ? '[Adjunto]' : '')
          await client.from('messages').upsert({
            conversation_id: conversation.id,
            meta_message_id: String(message.id),
            direction,
            body,
            status: direction === 'outgoing' ? 'sent' : 'received',
            meta_created_at: new Date(message.created_time).toISOString(),
          }, { onConflict: 'meta_message_id' })
          syncedMessages++
        }
      }
    }
    return response({
      ok: true,
      conversations: syncedConversations,
      messages: syncedMessages,
    })
  } catch (error) {
    if (error instanceof Response) return error
    const message = error.message ?? String(error)
    if (
      message.includes('(#10)') ||
      message.toLowerCase().includes('permission') ||
      message.toLowerCase().includes('pages_messaging')
    ) {
      return response({
        ok: false,
        meta_permission_denied: true,
        error:
          'Meta aÃºn no permite leer Messenger; se mostrarÃ¡n mensajes recibidos por webhook o pruebas locales.',
      })
    }
    return response({ error: message }, 500)
  }
})
