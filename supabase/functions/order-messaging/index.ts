import {
  adminClient,
  authenticatedUser,
  corsHeaders,
  graph,
  pageToken,
  response,
  template,
} from '../_shared/core.ts'

async function selectedPage(client: ReturnType<typeof adminClient>, userId: string) {
  const { data, error } = await client
    .from('facebook_pages')
    .select()
    .eq('owner_id', userId)
    .eq('is_selected', true)
    .eq('access_status', 'active')
    .maybeSingle()
  if (error) throw error
  if (!data) throw new Error('No hay página conectada.')
  return data
}

async function templateBody(
  client: ReturnType<typeof adminClient>,
  ownerId: string,
  kind: string,
  fallback: string,
) {
  const { data } = await client
    .from('message_templates')
    .select('body')
    .eq('owner_id', ownerId)
    .eq('kind', kind)
    .maybeSingle()
  return data?.body ?? fallback
}

async function sendText(pageMetaId: string, token: string, psid: string, text: string) {
  return graph(`${pageMetaId}/messages`, token, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      recipient: { id: psid },
      messaging_type: 'RESPONSE',
      message: { text },
    }),
  })
}

async function sendUtilityOrderTemplate(
  pageMetaId: string,
  token: string,
  psid: string,
  price: number,
  deliveryDetail: string,
) {
  return graph(`${pageMetaId}/messages`, token, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      recipient: { id: psid },
      message: {
        template: {
          name: 'pedido_confirmado_v2',
          language: { code: 'es_MX' },
          components: [
            {
              type: 'BODY',
              parameters: [
                { type: 'text', text: `$${price}` },
                { type: 'text', text: deliveryDetail },
              ],
            },
          ],
        },
      },
    }),
  })
}

async function sendImage(pageMetaId: string, token: string, psid: string, url: string) {
  return graph(`${pageMetaId}/messages`, token, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      recipient: { id: psid },
      messaging_type: 'RESPONSE',
      message: {
        attachment: {
          type: 'image',
          payload: { url, is_reusable: false },
        },
      },
    }),
  })
}

async function storeOutgoing(
  client: ReturnType<typeof adminClient>,
  conversationId: string,
  body: string,
  metaMessageId: string | null,
) {
  await client.from('messages').insert({
    conversation_id: conversationId,
    meta_message_id: metaMessageId,
    direction: 'outgoing',
    body,
    status: metaMessageId ? 'sent' : 'failed',
    meta_created_at: new Date().toISOString(),
  })
  await client
    .from('conversations')
    .update({ last_message_at: new Date().toISOString() })
    .eq('id', conversationId)
}

function isWindowOpen(conversation: Record<string, unknown>) {
  const value = conversation.can_message_until
  if (!value) return false
  return new Date(String(value)).getTime() > Date.now()
}

async function processConversation(
  client: ReturnType<typeof adminClient>,
  page: Record<string, any>,
  token: string,
  conversation: Record<string, any>,
  text: string,
  imageUrls: string[] = [],
) {
  if (!isWindowOpen(conversation)) {
    await client.from('alerts').insert({
      owner_id: page.owner_id,
      page_id: page.id,
      severity: 'warning',
      kind: 'messenger_window_closed',
      title: 'Ventana de Messenger cerrada',
      body: `No se pudo enviar a ${conversation.messenger_psid}.`,
    })
    return { sent: false, reason: 'closed_window' }
  }
  try {
    for (const imageUrl of imageUrls) {
      await sendImage(page.meta_page_id, token, conversation.messenger_psid, imageUrl)
      await storeOutgoing(client, conversation.id, '[Foto enviada]', null)
    }
    const payload = await sendText(page.meta_page_id, token, conversation.messenger_psid, text)
    await storeOutgoing(client, conversation.id, text, payload.message_id ?? null)
    return { sent: true }
  } catch (error) {
    const message = error.message ?? String(error)
    await client.from('alerts').insert({
      owner_id: page.owner_id,
      page_id: page.id,
      severity: 'error',
      kind: 'messenger_send_failed',
      title: 'Messenger rechazó el envío',
      body: message,
    })
    await storeOutgoing(client, conversation.id, text, null)
    return { sent: false, reason: message }
  }
}

async function processOrderConfirmation(
  client: ReturnType<typeof adminClient>,
  page: Record<string, any>,
  token: string,
  conversation: Record<string, any>,
  text: string,
  price: number,
  deliveryDetail: string,
  imageUrls: string[] = [],
) {
  const result = await processConversation(client, page, token, conversation, text, imageUrls)
  if (result.sent || result.reason !== 'closed_window') {
    return { ...result, photos_sent: result.sent ? imageUrls.length : 0 }
  }
  try {
    const payload = await sendUtilityOrderTemplate(
      page.meta_page_id,
      token,
      conversation.messenger_psid,
      price,
      deliveryDetail,
    )
    await storeOutgoing(
      client,
      conversation.id,
      `Pedido confirmado: $${price}. Entrega: ${deliveryDetail}.`,
      payload.message_id ?? null,
    )
    if (imageUrls.length > 0) {
      await client.from('alerts').insert({
        owner_id: page.owner_id,
        page_id: page.id,
        severity: 'warning',
        kind: 'messenger_photos_blocked_closed_window',
        title: 'Fotos no enviadas por ventana cerrada',
        body:
          `Se confirmó el pedido por template Utility, pero Meta no permite enviar ${imageUrls.length} foto(s) fuera de la ventana de 24 horas.`,
      })
      await storeOutgoing(
        client,
        conversation.id,
        `[${imageUrls.length} foto(s) no enviadas: ventana de Messenger cerrada]`,
        null,
      )
    }
    return {
      sent: true,
      via_template: true,
      photos_sent: 0,
      photos_blocked: imageUrls.length,
    }
  } catch (error) {
    const message = error.message ?? String(error)
    await client.from('alerts').insert({
      owner_id: page.owner_id,
      page_id: page.id,
      severity: 'error',
      kind: 'messenger_utility_template_failed',
      title: 'Meta rechazó el template Utility',
      body: message,
    })
    return { sent: false, reason: message, via_template: true }
  }
}

async function imageUrlsFromBody(
  client: ReturnType<typeof adminClient>,
  page: Record<string, any>,
  body: Record<string, any>,
) {
  const rawList = Array.isArray(body.attachment_storage_paths)
    ? body.attachment_storage_paths
    : body.attachment_storage_path
      ? [body.attachment_storage_path]
      : []
  const urls: string[] = []
  const seen = new Set<string>()
  for (const raw of rawList) {
    const key = String(raw ?? '').trim()
    if (!key || seen.has(key)) continue
    seen.add(key)
    const url = await imageUrlFromAttachment(client, page, key)
    if (url) urls.push(url)
  }
  return urls
}

async function imageUrlFromAttachment(
  client: ReturnType<typeof adminClient>,
  page: Record<string, any>,
  attachment: unknown,
) {
  if (!attachment) return undefined
  const attachmentPath = String(attachment)
  if (attachmentPath.startsWith('http://') || attachmentPath.startsWith('https://')) {
    return attachmentPath
  }
  const { data, error } = await client.storage
    .from('auction-media')
    .createSignedUrl(attachmentPath, 3600)
  if (error) {
    await client.from('alerts').insert({
      owner_id: page.owner_id,
      page_id: page.id,
      severity: 'warning',
      kind: 'order_attachment_missing',
      title: 'Foto de pedido no encontrada',
      body: `No se pudo anexar la foto ${attachmentPath}. Se intentará enviar sólo el texto.`,
    })
    return undefined
  }
  return data.signedUrl
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const user = await authenticatedUser(req)
    const client = adminClient()
    const body = await req.json().catch(() => ({}))
    const action = String(body.action ?? '')
    const page = await selectedPage(client, user.id)
    const token = await pageToken(client, page.id)

    if (action === 'manual_order_confirmation') {
      const conversationId = String(body.conversation_id ?? '')
      const price = Number(body.price ?? 0)
      const deliveryDetail = String(body.delivery_detail ?? 'por confirmar')
      const locationName = String(body.delivery_location_name ?? '')
      const fixedBoothName = String(body.fixed_booth_name ?? '')
      const zone = body.zone ? Number(body.zone) : null
      const boothNumber = body.booth_number ? Number(body.booth_number) : null
      const imageUrls = await imageUrlsFromBody(client, page, body)
      const { data: conversation, error } = await client
        .from('conversations')
        .select()
        .eq('id', conversationId)
        .eq('owner_id', user.id)
        .single()
      if (error) throw error
      const raw = await templateBody(
        client,
        user.id,
        'manual_order_confirmation',
        'Confirmo tu pedido para este Domingo en Mundo Divertido, el total serian {precio}.',
      )
      const text = template(raw, {
        precio: `$${price}`,
        detalleEntrega: deliveryDetail,
        lugarEntrega: locationName || deliveryDetail,
        puesto: fixedBoothName || 'Tokyo Morningstore',
        zona: zone ?? '',
        numeroPuesto: boothNumber ?? '',
      })
      const result = await processOrderConfirmation(
        client,
        page,
        token,
        conversation,
        text,
        price,
        deliveryDetail,
        imageUrls,
      )
      return response({ ok: true, ...result })
    }

    if (action === 'bulk_delivery_reminder' || action === 'bulk_arrival_notice') {
      const deliveryLocationId = body.delivery_location_id ? String(body.delivery_location_id) : null
      const deliveryDetail = String(body.delivery_detail ?? 'por confirmar')
      const description = String(body.description ?? '')
      const until = String(body.until ?? '')
      const imageUrls = await imageUrlsFromBody(client, page, body)
      let query = client
        .from('orders')
        .select('id,total,customer_id,customers(display_name)')
        .eq('owner_id', user.id)
        .eq('page_id', page.id)
        .eq('delivery_status', 'pending')
      if (deliveryLocationId) query = query.eq('delivery_location_id', deliveryLocationId)
      const { data: orders, error } = await query
      if (error) throw error
      const raw = await templateBody(
        client,
        user.id,
        action,
        action === 'bulk_delivery_reminder'
          ? 'Hola {cliente}, te recuerdo que este domingo te entrego tu pedido en {detalleEntrega}. Total: {total}.'
          : 'Ya estoy en {detalleEntrega}. Voy vestido así: {descripcion}. Estaré hasta {horaLimite}.',
      )
      let sent = 0
      let failed = 0
      let skipped = 0
      const seen = new Set<string>()
      for (const order of orders ?? []) {
        const { data: conversation } = await client
          .from('conversations')
          .select()
          .eq('owner_id', user.id)
          .eq('page_id', page.id)
          .eq('customer_id', order.customer_id)
          .order('last_message_at', { ascending: false })
          .limit(1)
          .maybeSingle()
        if (!conversation || seen.has(conversation.id)) {
          skipped++
          continue
        }
        seen.add(conversation.id)
        const text = template(raw, {
          cliente: order.customers?.display_name ?? 'cliente',
          detalleEntrega: deliveryDetail,
          total: `$${order.total ?? 0}`,
          descripcion: description,
          horaLimite: until,
        })
        const result = await processConversation(
          client,
          page,
          token,
          conversation,
          text,
          action === 'bulk_arrival_notice' ? imageUrls : [],
        )
        if (result.sent) sent++
        else failed++
      }
      return response({ ok: true, sent, failed, skipped })
    }

    return response({ error: 'Acción no soportada.' }, 400)
  } catch (error) {
    if (error instanceof Response) return error
    const message = error.message ?? String(error)
    if (message.includes('(#10)')) {
      return response({
        ok: false,
        meta_permission_denied: true,
        error: 'Meta aún no permite enviar Messenger desde la app. El pedido se conserva.',
      })
    }
    return response({ error: message }, 500)
  }
})
