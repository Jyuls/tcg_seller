import { corsHeaders, response } from '../_shared/core.ts'

Deno.serve((req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  return response({
    ok: true,
    imported: 0,
    disabled: true,
    message: 'La importación externa está pausada en el MVP de subastas.',
  })
})
