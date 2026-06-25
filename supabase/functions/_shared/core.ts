import { createClient, SupabaseClient } from 'npm:@supabase/supabase-js@2'

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret, x-hub-signature-256',
}

export const graphVersion = Deno.env.get('META_GRAPH_VERSION') ?? 'v25.0'
export const graphBase = `https://graph.facebook.com/${graphVersion}`

export function adminClient(): SupabaseClient {
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY')
  if (!key) throw new Error('SUPABASE_SECRET_KEY no está disponible')
  return createClient(Deno.env.get('SUPABASE_URL')!, key, { auth: { persistSession: false } })
}

export async function authenticatedUser(req: Request) {
  const authorization = req.headers.get('Authorization')
  if (!authorization) throw new Response('No autorizado', { status: 401 })
  const client = adminClient()
  const { data, error } = await client.auth.getUser(authorization.replace(/^Bearer\s+/i, ''))
  if (error || !data.user) throw new Response('Sesión inválida', { status: 401 })
  return data.user
}

export function response(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

function bytesToBase64(bytes: Uint8Array) {
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary)
}

function base64ToBytes(value: string) {
  const binary = atob(value)
  return Uint8Array.from(binary, (character) => character.charCodeAt(0))
}

async function encryptionKey() {
  const encoded = Deno.env.get('TOKEN_ENCRYPTION_KEY')
  let raw: Uint8Array
  if (encoded) {
    raw = base64ToBytes(encoded)
    if (raw.length !== 32) throw new Error('TOKEN_ENCRYPTION_KEY debe contener 32 bytes en Base64')
  } else {
    const appSecret = Deno.env.get('META_APP_SECRET')
    if (!appSecret) throw new Error('Falta META_APP_SECRET')
    raw = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${appSecret}:${Deno.env.get('SUPABASE_URL')}:tcg-token-encryption-v1`)))
  }
  return crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt', 'decrypt'])
}

export async function encryptToken(token: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await encryptionKey(), new TextEncoder().encode(token))
  return { encrypted: bytesToBase64(new Uint8Array(encrypted)), iv: bytesToBase64(iv) }
}

export async function decryptToken(encrypted: string, iv: string) {
  const clear = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: base64ToBytes(iv) }, await encryptionKey(), base64ToBytes(encrypted))
  return new TextDecoder().decode(clear)
}

export async function graph(path: string, token: string, options: RequestInit = {}) {
  const separator = path.includes('?') ? '&' : '?'
  const url = `${graphBase}/${path}${separator}access_token=${encodeURIComponent(token)}`
  const result = await fetch(url, options)
  const payload = await result.json()
  if (!result.ok || payload.error) throw new Error(payload.error?.message ?? `Meta respondió ${result.status}`)
  return payload
}

export async function pageToken(client: SupabaseClient, pageId: string) {
  const { data, error } = await client.rpc('service_get_page_credential', { target_page_id: pageId })
  const credential = Array.isArray(data) ? data[0] : data
  if (error || !credential) throw new Error('La página no tiene un token válido')
  return decryptToken(credential.encrypted_page_token, credential.encryption_iv)
}

export async function verifyCron(req: Request, client: SupabaseClient) {
  const provided = req.headers.get('x-cron-secret')
  if (!provided) return false
  const { data } = await client.rpc('service_get_cron_secret')
  if (!data) return false
  const a = new TextEncoder().encode(provided)
  const b = new TextEncoder().encode(data)
  if (a.length !== b.length) return false
  let difference = 0
  for (let index = 0; index < a.length; index++) difference |= a[index] ^ b[index]
  return difference === 0
}

export function template(body: string, variables: Record<string, string | number>) {
  return Object.entries(variables).reduce((result, [name, value]) => result.replaceAll(`{${name}}`, String(value)), body)
}
