import { authenticatedUser, adminClient, corsHeaders, encryptToken, graph, graphBase, response } from '../_shared/core.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const user = await authenticatedUser(req)
    const { access_token } = await req.json()
    if (!access_token) return response({ error: 'Falta access_token' }, 400)
    const appId = Deno.env.get('META_APP_ID')
    const appSecret = Deno.env.get('META_APP_SECRET')
    if (!appId || !appSecret) return response({ error: 'Meta todavía no está configurado en Supabase' }, 503)
    const exchange = new URL(`${graphBase}/oauth/access_token`)
    exchange.searchParams.set('grant_type', 'fb_exchange_token')
    exchange.searchParams.set('client_id', appId)
    exchange.searchParams.set('client_secret', appSecret)
    exchange.searchParams.set('fb_exchange_token', access_token)
    const tokenResponse = await fetch(exchange)
    const tokenPayload = await tokenResponse.json()
    if (!tokenResponse.ok || !tokenPayload.access_token) throw new Error(tokenPayload.error?.message ?? 'No se pudo extender el token')
    const longToken = tokenPayload.access_token as string
    const profileResponse = await fetch(`${graphBase}/me?fields=id,name&access_token=${encodeURIComponent(longToken)}`)
    const profile = await profileResponse.json()
    if (!profileResponse.ok) throw new Error(profile.error?.message ?? 'No se pudo leer el perfil')
    const pagesResponse = await fetch(`${graphBase}/me/accounts?fields=id,name,category,picture,access_token&limit=100&access_token=${encodeURIComponent(longToken)}`)
    const pagesPayload = await pagesResponse.json()
    if (!pagesResponse.ok) throw new Error(pagesPayload.error?.message ?? 'No se pudieron consultar las páginas')
    const client = adminClient()
    const encryptedUser = await encryptToken(longToken)
    await client.from('meta_connections').upsert({ user_id: user.id, meta_user_id: profile.id, status: 'connected', token_expires_at: tokenPayload.expires_in ? new Date(Date.now() + tokenPayload.expires_in * 1000).toISOString() : null, last_error: null, updated_at: new Date().toISOString() })
    await client.rpc('service_store_user_credential', { target_user_id: user.id, encrypted_token: encryptedUser.encrypted, token_iv: encryptedUser.iv })
    const pages = []
    for (const item of pagesPayload.data ?? []) {
      const { data: page, error } = await client.from('facebook_pages').upsert({ owner_id: user.id, meta_page_id: item.id, name: item.name, category: item.category, picture_url: item.picture?.data?.url, access_status: 'active', updated_at: new Date().toISOString() }, { onConflict: 'owner_id,meta_page_id' }).select().single()
      if (error) throw error
      const encryptedPage = await encryptToken(item.access_token)
      await client.rpc('service_store_page_credential', { target_page_id: page.id, encrypted_token: encryptedPage.encrypted, token_iv: encryptedPage.iv })
      try {
        await graph(`${item.id}/subscribed_apps`, item.access_token, {
          method: 'POST',
          body: new URLSearchParams({ subscribed_fields: 'feed' }),
        })
      } catch (_) {
        // La reconciliación directa mantiene las pujas visibles si el webhook aún no está habilitado.
      }
      pages.push(page)
    }
    return response({ pages })
  } catch (error) {
    if (error instanceof Response) return error
    return response({ error: error.message ?? String(error) }, 500)
  }
})
