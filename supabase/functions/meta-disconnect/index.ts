import { adminClient, authenticatedUser, corsHeaders, decryptToken, graph, response } from '../_shared/core.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const user = await authenticatedUser(req)
    const client = adminClient()
    let remoteRevoked = false
    let remoteError: string | null = null
    const { data } = await client.rpc('service_get_user_credential', { target_user_id: user.id })
    const credential = Array.isArray(data) ? data[0] : data
    if (credential) {
      try {
        const token = await decryptToken(credential.encrypted_user_token, credential.encryption_iv)
        await graph('me/permissions', token, { method: 'DELETE' })
        remoteRevoked = true
      } catch (error) {
        remoteError = error instanceof Error ? error.message : String(error)
      }
    }
    await client.rpc('service_clear_meta_credentials', { target_user_id: user.id })
    await client.from('facebook_pages').update({ is_selected: false, access_status: 'revoked', updated_at: new Date().toISOString() }).eq('owner_id', user.id)
    await client.from('meta_connections').upsert({ user_id: user.id, status: 'revoked', last_error: remoteError, updated_at: new Date().toISOString() })
    return response({ disconnected: true, remote_revoked: remoteRevoked, warning: remoteError })
  } catch (error) {
    if (error instanceof Response) return error
    return response({ error: error instanceof Error ? error.message : String(error) }, 500)
  }
})
