import { adminClient, authenticatedUser, corsHeaders, graph, pageToken, response } from '../_shared/core.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const user = await authenticatedUser(req)
    const body = await req.json()
    const ids: string[] = body.conversation_ids ?? (body.conversation_id ? [body.conversation_id] : [])
    const message = String(body.message ?? '').trim()
    if (!ids.length || !message) return response({ error: 'Faltan destinatarios o mensaje' }, 400)
    const client = adminClient()
    const results = []
    for (const id of ids) {
      const { data: conversation } = await client.from('conversations').select('*, facebook_pages(*)').eq('id', id).eq('owner_id', user.id).single()
      if (!conversation) { results.push({ id, error: 'Conversación inexistente' }); continue }
      if (!conversation.can_message_until || new Date(conversation.can_message_until) <= new Date()) { results.push({ id, error: 'Ventana de mensajería cerrada' }); continue }
      try {
        const token = await pageToken(client, conversation.page_id)
        const payload = await graph(`${conversation.facebook_pages.meta_page_id}/messages`, token, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ recipient: { id: conversation.messenger_psid }, messaging_type: 'RESPONSE', message: { text: message } }) })
        await client.from('messages').insert({ conversation_id: id, meta_message_id: payload.message_id, direction: 'outgoing', body: message, status: 'sent', meta_created_at: new Date().toISOString() })
        await client.from('conversations').update({ last_message_at: new Date().toISOString() }).eq('id', id)
        results.push({ id, sent: true })
      } catch (error) { results.push({ id, error: error.message ?? String(error) }) }
    }
    return response({ results }, results.some((result) => result.sent) ? 200 : 409)
  } catch (error) {
    if (error instanceof Response) return error
    return response({ error: error.message ?? String(error) }, 500)
  }
})
