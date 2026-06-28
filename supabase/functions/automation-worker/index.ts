import {
  adminClient,
  authenticatedUser,
  corsHeaders,
  graph,
  pageToken,
  response,
  template,
  verifyCron,
} from '../_shared/core.ts'

type Client = ReturnType<typeof adminClient>

const defaults: Record<string, string> = {
  auction_reminder:
    'Esta subasta termina a las {horaCierre}. Puja mas alta: {pujaActual}.',
  auction_reminder_no_bids:
    'Esta subasta termina a las {horaCierre}. Aún sin pujas.',
  winner_linked: 'Ganaste esta subasta. Te enviÃ© los detalles por inbox.',
  winner_unlinked:
    'Ganaste esta subasta. Enviame mensaje para confirmar tu pedido.',
  winner_window_closed:
    'Ganaste esta subasta. MÃ¡ndanos un nuevo inbox con el cÃ³digo {codigoConfirmacion} para enviarte los detalles.',
  winner_order_summary:
    'Tu pedido de esta subasta: {cantidad} artÃ­culo(s), total {total}.',
}

function confirmationCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  const bytes = crypto.getRandomValues(new Uint8Array(6))
  return [...bytes].map((byte) => alphabet[byte % alphabet.length]).join('')
}

function validAmount(message: string) {
  const match = message.match(/^\s*\$?\s*([0-9]+)\s*(?:pesos?|mxn)?\s*$/i)
  if (!match) return null
  const amount = Number(match[1])
  return Number.isSafeInteger(amount) ? amount : null
}

function hourLabel(value: string) {
  return new Intl.DateTimeFormat('es-MX', {
    timeZone: 'America/Tijuana',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  }).format(new Date(value))
}

async function templates(client: Client, ownerId: string, kinds: string[]) {
  const { data } = await client
    .from('message_templates')
    .select('kind,body')
    .eq('owner_id', ownerId)
    .in('kind', kinds)
  return Object.fromEntries((data ?? []).map((entry) => [entry.kind, entry.body]))
}

async function alert(
  client: Client,
  ownerId: string,
  severity: string,
  kind: string,
  title: string,
  body: string,
  entityId?: string,
) {
  await client.from('alerts').insert({
    owner_id: ownerId,
    severity,
    kind,
    title,
    body,
    entity_type: entityId ? 'publication' : null,
    entity_id: entityId,
  })
}

async function attachmentPhotoIds(postId: string, token: string) {
  const payload = await graph(
    `${postId}?fields=attachments.limit(100){target,subattachments.limit(100){target}}`,
    token,
  )
  const attachments = payload.attachments?.data ?? []
  const nested = attachments.flatMap((entry: Record<string, any>) =>
    entry.subattachments?.data ?? []
  )
  const source = nested.length ? nested : attachments
  return source.map((entry: Record<string, any>) => entry.target?.id).filter(Boolean) as string[]
}

async function publishAuction(client: Client, publicationId: string) {
  const { data: publication, error } = await client
    .from('publications')
    .select('*, facebook_pages(*)')
    .eq('id', publicationId)
    .single()
  if (error || !publication) throw error ?? new Error('PublicaciÃ³n inexistente')
  if (publication.meta_post_id && publication.status === 'active') return
  if (publication.publication_type && publication.publication_type !== 'auction') {
    throw new Error('SÃ³lo se publican subastas desde este MVP')
  }

  const { data: items } = await client
    .from('publication_items')
    .select()
    .eq('publication_id', publicationId)
    .order('position')
  if (!items?.length) throw new Error('La publicaciÃ³n no tiene fotografÃ­as')

  const token = await pageToken(client, publication.page_id)
  await client
    .from('publications')
    .update({ status: 'publishing', last_error: null })
    .eq('id', publicationId)

  const mediaIds: string[] = []
  for (const item of items) {
    if (item.meta_photo_id) {
      mediaIds.push(item.meta_photo_id)
      continue
    }
    const { data: signed, error: signedError } = await client.storage
      .from('auction-media')
      .createSignedUrl(item.storage_path, 3600)
    if (signedError) throw signedError
    const photo = await graph(`${publication.facebook_pages.meta_page_id}/photos`, token, {
      method: 'POST',
      body: new URLSearchParams({ url: signed.signedUrl, published: 'false' }),
    })
    await client
      .from('publication_items')
      .update({ meta_photo_id: photo.id, upload_status: 'uploaded' })
      .eq('id', item.id)
    mediaIds.push(photo.id)
  }

  const postBody = new URLSearchParams({ message: publication.body ?? '' })
  mediaIds.forEach((id, index) =>
    postBody.set(`attached_media[${index}]`, JSON.stringify({ media_fbid: id }))
  )
  const post = await graph(`${publication.facebook_pages.meta_page_id}/feed`, token, {
    method: 'POST',
    body: postBody,
  })

  const finalPhotoIds = await attachmentPhotoIds(post.id, token).catch(() => [])
  for (let index = 0; index < items.length && index < finalPhotoIds.length; index++) {
    await client
      .from('publication_items')
      .update({ meta_photo_id: finalPhotoIds[index] })
      .eq('id', items[index].id)
  }

  await client
    .from('publications')
    .update({
      status: 'active',
      meta_post_id: post.id,
      published_at: publication.published_at ?? new Date().toISOString(),
      last_error: null,
    })
    .eq('id', publicationId)

  await client.from('automation_jobs').upsert({
    owner_id: publication.owner_id,
    kind: 'close_auction',
    entity_id: publicationId,
    run_at: new Date(new Date(publication.ends_at).getTime() + 60_000).toISOString(),
    idempotency_key: `close:${publicationId}`,
  }, { onConflict: 'idempotency_key' })
}

async function allComments(photoId: string, token: string) {
  const rows: Record<string, any>[] = []
  let path =
    `${photoId}/comments?fields=id,message,from{id,name},created_time&limit=100&order=chronological`
  for (let page = 0; path && page < 30; page++) {
    const payload = await graph(path, token)
    rows.push(...(payload.data ?? []))
    const next = payload.paging?.next as string | undefined
    path = next ? next.replace(/^https:\/\/graph\.facebook\.com\/v[0-9.]+\//, '') : ''
  }
  return rows
}

async function storeCommentAndBid(
  client: Client,
  publication: Record<string, any>,
  item: Record<string, any>,
  raw: Record<string, any>,
) {
  const created = new Date(raw.created_time as string)
  const amount = validAmount(String(raw.message ?? ''))
  const beforeClose = created.getTime() < new Date(publication.ends_at).getTime()
  const onGrid = amount !== null &&
    amount >= publication.starting_bid &&
    (amount - publication.starting_bid) % publication.bid_increment === 0
  const isValid = amount !== null && beforeClose && onGrid
  const rejection = amount === null ? 'format' : !beforeClose ? 'after_close' : !onGrid
    ? 'minimum_bid'
    : null
  const { data: stored, error } = await client.from('meta_comments').upsert({
    publication_item_id: item.id,
    meta_comment_id: String(raw.id),
    author_meta_id: raw.from?.id ? String(raw.from.id) : null,
    author_name: raw.from?.name ? String(raw.from.name) : null,
    message: String(raw.message ?? ''),
    meta_created_at: created.toISOString(),
    raw_payload: raw,
  }, { onConflict: 'meta_comment_id' }).select().single()
  if (error) throw error
  if (amount !== null) {
    await client.from('bids').upsert({
      comment_id: stored.id,
      publication_item_id: item.id,
      amount,
      meta_created_at: created.toISOString(),
      is_valid: isValid,
      rejection_reason: rejection,
    }, { onConflict: 'comment_id' })
  }
  return { ...stored, amount, is_valid: isValid }
}

async function refreshWinner(client: Client, itemId: string) {
  const { data: highest } = await client
    .from('bids')
    .select('comment_id,amount')
    .eq('publication_item_id', itemId)
    .eq('is_valid', true)
    .order('amount', { ascending: false })
    .order('meta_created_at', { ascending: true })
    .limit(1)
    .maybeSingle()
  await client
    .from('publication_items')
    .update({
      winning_comment_id: highest?.comment_id ?? null,
      winning_amount: highest?.amount ?? null,
      resolution_status: highest ? 'open' : 'open',
    })
    .eq('id', itemId)
}

async function syncAuction(client: Client, publicationId: string) {
  const { data: publication, error } = await client
    .from('publications')
    .select('*, facebook_pages(*)')
    .eq('id', publicationId)
    .single()
  if (error || !publication) throw error ?? new Error('PublicaciÃ³n inexistente')
  if (publication.publication_type && publication.publication_type !== 'auction') return

  const token = await pageToken(client, publication.page_id)
  try {
    await graph(`${publication.facebook_pages.meta_page_id}/subscribed_apps`, token, {
      method: 'POST',
      body: new URLSearchParams({
        subscribed_fields: 'feed,messages,messaging_postbacks',
      }),
    })
  } catch (_) {
    // La reconciliaciÃ³n directa sigue funcionando aunque Meta no permita algÃºn webhook.
  }

  const { data: items } = await client
    .from('publication_items')
    .select()
    .eq('publication_id', publicationId)
    .order('position')

  if (publication.meta_post_id) {
    const ids = await attachmentPhotoIds(publication.meta_post_id, token).catch(() => [])
    for (let index = 0; index < items.length && index < ids.length; index++) {
      if (ids[index] && items[index].meta_photo_id !== ids[index]) {
        items[index].meta_photo_id = ids[index]
        await client.from('publication_items').update({ meta_photo_id: ids[index] }).eq(
          'id',
          items[index].id,
        )
      }
    }
  }

  for (const item of items ?? []) {
    if (!item.meta_photo_id) continue
    const comments = await allComments(item.meta_photo_id, token)
    for (const raw of comments) await storeCommentAndBid(client, publication, item, raw)
    await client
      .from('publication_items')
      .update({ comment_count: comments.length })
      .eq('id', item.id)
    await refreshWinner(client, item.id)
  }
}

async function remindAuction(client: Client, publicationId: string, force = false) {
  const { data: publication, error } = await client
    .from('publications')
    .select('*, facebook_pages(*)')
    .eq('id', publicationId)
    .single()
  if (error || !publication) throw error ?? new Error('PublicaciÃ³n inexistente')
  const token = await pageToken(client, publication.page_id)
  const loadedTemplates = await templates(client, publication.owner_id, [
    'auction_reminder',
    'auction_reminder_no_bids',
  ])
  await syncAuction(client, publicationId)
  const { data: items } = await client
    .from('publication_items')
    .select()
    .eq('publication_id', publicationId)
    .order('position')
  for (const item of items ?? []) {
    if (!item.meta_photo_id) continue
    if (!force && item.reminder_sent_at) continue
    const kind = item.winning_amount ? 'auction_reminder' : 'auction_reminder_no_bids'
    const message = template(loadedTemplates[kind] ?? defaults[kind], {
      horaCierre: hourLabel(publication.ends_at),
      pujaActual: item.winning_amount ? `$${item.winning_amount}` : 'sin pujas',
    })
    try {
      const reply = await graph(`${item.meta_photo_id}/comments`, token, {
        method: 'POST',
        body: new URLSearchParams({ message }),
      })
      await client
        .from('publication_items')
        .update({
          reminder_meta_comment_id: reply.id,
          reminder_sent_at: new Date().toISOString(),
          reminder_count: Number(item.reminder_count ?? 0) + 1,
          reminder_last_error: null,
        })
        .eq('id', item.id)
    } catch (error) {
      await client
        .from('publication_items')
        .update({ reminder_last_error: error.message ?? String(error) })
        .eq('id', item.id)
      await alert(
        client,
        publication.owner_id,
        'error',
        'auction_reminder_failed',
        'No se pudo enviar un recordatorio',
        error.message ?? String(error),
        publication.id,
      )
    }
  }
}

async function customerForWinner(
  client: Client,
  publication: Record<string, any>,
  winner: Record<string, any>,
) {
  const commenterId = winner.author_meta_id as string | null
  if (commenterId) {
    const { data: identity } = await client
      .from('customer_meta_identities')
      .select('*, customers(*)')
      .eq('page_id', publication.page_id)
      .eq('commenter_id', commenterId)
      .maybeSingle()
    if (identity) return { customer: identity.customers, identity }
  }

  const authorName = String(winner.author_name ?? '').trim()
  if (authorName) {
    const { data: existingCustomer } = await client
      .from('customers')
      .select()
      .eq('owner_id', publication.owner_id)
      .eq('page_id', publication.page_id)
      .eq('display_name', authorName)
      .maybeSingle()
    if (existingCustomer) {
      let { data: existingIdentity } = await client
        .from('customer_meta_identities')
        .select()
        .eq('customer_id', existingCustomer.id)
        .eq('page_id', publication.page_id)
        .maybeSingle()
      if (!existingIdentity) {
        const { data: createdIdentity, error: identityError } = await client
          .from('customer_meta_identities')
          .insert({
            customer_id: existingCustomer.id,
            page_id: publication.page_id,
            commenter_id: commenterId,
            confirmation_code: confirmationCode(),
          })
          .select()
          .single()
        if (identityError) throw identityError
        existingIdentity = createdIdentity
      } else if (!existingIdentity.confirmation_code) {
        const { data: updatedIdentity, error: updateError } = await client
          .from('customer_meta_identities')
          .update({ confirmation_code: confirmationCode() })
          .eq('id', existingIdentity.id)
          .select()
          .single()
        if (updateError) throw updateError
        existingIdentity = updatedIdentity
      }
      return { customer: existingCustomer, identity: existingIdentity }
    }
  }

  const { data: customer, error } = await client
    .from('customers')
    .insert({
      owner_id: publication.owner_id,
      page_id: publication.page_id,
      display_name: authorName || 'Usuario de Facebook',
      is_provisional: true,
    })
    .select()
    .single()
  if (error) throw error

  const { data: identity, error: identityError } = await client
    .from('customer_meta_identities')
    .insert({
      customer_id: customer.id,
      page_id: publication.page_id,
      commenter_id: commenterId,
      confirmation_code: confirmationCode(),
    })
    .select()
    .single()
  if (identityError) throw identityError
  return { customer, identity }
}

async function orderForWinner(client: Client, publication: Record<string, any>, customerId: string) {
  const { data: existing } = await client
    .from('orders')
    .select()
    .eq('customer_id', customerId)
    .eq('payment_status', 'pending')
    .eq('delivery_status', 'pending')
    .maybeSingle()
  if (existing) return existing
  const { data, error } = await client
    .from('orders')
    .insert({ owner_id: publication.owner_id, page_id: publication.page_id, customer_id: customerId })
    .select()
    .single()
  if (!error) return data
  if (error.code === '23505') {
    const { data: concurrent, error: concurrentError } = await client
      .from('orders')
      .select()
      .eq('customer_id', customerId)
      .eq('payment_status', 'pending')
      .eq('delivery_status', 'pending')
      .single()
    if (!concurrentError) return concurrent
  }
  throw error
}

async function conversationForIdentity(
  client: Client,
  ownerId: string,
  pageId: string,
  customerId: string,
  canMessageUntil?: string,
  psid?: string,
) {
  if (!psid) return null
  const { data } = await client
    .from('conversations')
    .select()
    .eq('page_id', pageId)
    .eq('messenger_psid', psid)
    .maybeSingle()
  if (data) return data
  const { data: created } = await client
    .from('conversations')
    .insert({
      owner_id: ownerId,
      page_id: pageId,
      customer_id: customerId,
      messenger_psid: psid,
      last_message_at: new Date().toISOString(),
      can_message_until: canMessageUntil ?? new Date().toISOString(),
    })
    .select()
    .maybeSingle()
  return created
}

async function sendMessengerText(
  client: Client,
  page: Record<string, any>,
  conversation: Record<string, any>,
  message: string,
) {
  const token = await pageToken(client, page.id)
  const payload = await graph(`${page.meta_page_id}/messages`, token, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      recipient: { id: conversation.messenger_psid },
      messaging_type: 'RESPONSE',
      message: { text: message },
    }),
  })
  await client.from('messages').insert({
    conversation_id: conversation.id,
    meta_message_id: payload.message_id,
    direction: 'outgoing',
    body: message,
    status: 'sent',
    meta_created_at: new Date().toISOString(),
  })
  return payload.message_id as string
}

async function sendMessengerImage(
  client: Client,
  page: Record<string, any>,
  conversation: Record<string, any>,
  imageUrl: string,
) {
  const token = await pageToken(client, page.id)
  const payload = await graph(`${page.meta_page_id}/messages`, token, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      recipient: { id: conversation.messenger_psid },
      messaging_type: 'RESPONSE',
      message: {
        attachment: {
          type: 'image',
          payload: { url: imageUrl, is_reusable: true },
        },
      },
    }),
  })
  await client.from('messages').insert({
    conversation_id: conversation.id,
    meta_message_id: payload.message_id,
    direction: 'outgoing',
    body: '[Foto de artÃ­culo ganado]',
    status: 'sent',
    meta_created_at: new Date().toISOString(),
  })
  return payload.message_id as string
}

async function sendWinnerBatch(client: Client, batchId: string) {
  const { data: batch } = await client
    .from('winner_notification_batches')
    .select('*, publications(*, facebook_pages(*)), conversations(*)')
    .eq('id', batchId)
    .single()
  if (!batch || batch.status === 'sent' || !batch.conversations) return
  if (!batch.conversations.can_message_until ||
    new Date(batch.conversations.can_message_until) <= new Date()) {
    await client
      .from('winner_notification_batches')
      .update({ status: 'skipped', last_error: 'Ventana de Messenger cerrada' })
      .eq('id', batchId)
    return
  }

  const page = batch.publications.facebook_pages
  const { data: media } = await client
    .from('winner_notification_media')
    .select('*, order_items(*)')
    .eq('batch_id', batchId)
    .order('position')
  await client.from('winner_notification_batches').update({ status: 'sending' }).eq('id', batchId)
  try {
    for (const entry of media ?? []) {
      if (entry.status === 'sent') continue
      let imageUrl = entry.order_items.photo_storage_path
      if (!String(imageUrl).startsWith('http')) {
        const { data: signed } = await client.storage.from('auction-media').createSignedUrl(imageUrl, 3600)
        imageUrl = signed?.signedUrl ?? imageUrl
      }
      const imageMessageId = await sendMessengerImage(client, page, batch.conversations, imageUrl)
      const captionId = await sendMessengerText(
        client,
        page,
        batch.conversations,
        `ArtÃ­culo ${entry.position + 1}: $${entry.order_items.price}`,
      )
      await client
        .from('winner_notification_media')
        .update({
          status: 'sent',
          image_meta_message_id: imageMessageId,
          caption_meta_message_id: captionId,
          sent_at: new Date().toISOString(),
          last_error: null,
        })
        .eq('id', entry.id)
    }
    const loadedTemplates = await templates(client, batch.owner_id, ['winner_order_summary'])
    const summary = template(loadedTemplates.winner_order_summary ?? defaults.winner_order_summary, {
      cantidad: batch.item_count,
      total: `$${batch.subtotal}`,
    })
    const summaryId = await sendMessengerText(client, page, batch.conversations, summary)
    await client
      .from('winner_notification_batches')
      .update({
        status: 'sent',
        summary_meta_message_id: summaryId,
        sent_at: new Date().toISOString(),
        last_error: null,
      })
      .eq('id', batchId)
  } catch (error) {
    await client
      .from('winner_notification_batches')
      .update({
        status: 'failed',
        attempts: Number(batch.attempts ?? 0) + 1,
        last_error: error.message ?? String(error),
      })
      .eq('id', batchId)
    await alert(
      client,
      batch.owner_id,
      'error',
      'winner_message_failed',
      'No se pudo enviar el resumen por Messenger',
      error.message ?? String(error),
      batch.publication_id,
    )
  }
}

async function closeAuction(client: Client, publicationId: string) {
  const { data: publication, error } = await client
    .from('publications')
    .select('*, facebook_pages(*)')
    .eq('id', publicationId)
    .single()
  if (error || !publication) throw error ?? new Error('PublicaciÃ³n inexistente')
  if (new Date() < new Date(new Date(publication.ends_at).getTime() + 60_000)) return

  await syncAuction(client, publicationId)
  const token = await pageToken(client, publication.page_id)
  const loadedTemplates = await templates(client, publication.owner_id, [
    'winner_linked',
    'winner_unlinked',
    'winner_window_closed',
  ])

  const { data: items } = await client
    .from('publication_items')
    .select('*, meta_comments!publication_items_winning_comment_fk(*)')
    .eq('publication_id', publicationId)
    .order('position')

  let needsReview = false
  const batchIds = new Set<string>()
  for (const item of items ?? []) {
    if (item.resolution_status === 'winner' && item.winner_reply_meta_id) continue
    const winner = item.meta_comments
    if (!winner || !item.winning_amount) {
      needsReview = true
      await client.from('publication_items').update({ resolution_status: 'review' }).eq('id', item.id)
      continue
    }

    if (!winner.author_meta_id) {
      needsReview = true
      const message = template(loadedTemplates.winner_unlinked ?? defaults.winner_unlinked, {
        codigoConfirmacion: '',
        precioGanador: `$${item.winning_amount}`,
      })
      let replyId = item.winner_reply_meta_id
      if (!replyId) {
        try {
          const reply = await graph(`${winner.meta_comment_id}/comments`, token, {
            method: 'POST',
            body: new URLSearchParams({ message }),
          })
          replyId = reply.id
        } catch (replyError) {
          await alert(
            client,
            publication.owner_id,
            'error',
            'winner_reply_failed',
            'No se pudo avisar al ganador',
            replyError.message ?? String(replyError),
            publication.id,
          )
        }
      }
      await client
        .from('publication_items')
        .update({
          resolution_status: 'review',
          confirmation_code: null,
          winner_reply_meta_id: replyId,
          winner_reply_kind: 'winner_unlinked',
          winner_replied_at: replyId ? new Date().toISOString() : null,
        })
        .eq('id', item.id)
      continue
    }

    const linked = await customerForWinner(client, publication, winner)
    const order = await orderForWinner(client, publication, linked.customer.id)
    const { data: orderItem, error: orderItemError } = await client
      .from('order_items')
      .upsert({
        order_id: order.id,
        publication_item_id: item.id,
        photo_storage_path: item.storage_path,
        source_label: `${publication.title} Â· ArtÃ­culo ${item.position + 1}`,
        price: item.winning_amount,
      }, { onConflict: 'publication_item_id' })
      .select()
      .single()
    if (orderItemError) throw orderItemError

    const psid = linked.identity.messenger_psid as string | undefined
    const eligibleUntil = linked.identity.messenger_eligible_until
      ? new Date(linked.identity.messenger_eligible_until)
      : null
    const canMessage = Boolean(psid && eligibleUntil && eligibleUntil > new Date())
    const replyKind = canMessage
      ? 'winner_linked'
      : psid
      ? 'winner_window_closed'
      : 'winner_unlinked'
    const message = template(loadedTemplates[replyKind] ?? defaults[replyKind], {
      codigoConfirmacion: linked.identity.confirmation_code ?? '',
    })

    let replyId = item.winner_reply_meta_id
    if (!replyId) {
      try {
        const reply = await graph(`${winner.meta_comment_id}/comments`, token, {
          method: 'POST',
          body: new URLSearchParams({ message }),
        })
        replyId = reply.id
      } catch (replyError) {
        await alert(
          client,
          publication.owner_id,
          'error',
          'winner_reply_failed',
          'No se pudo avisar al ganador',
          replyError.message ?? String(replyError),
          publication.id,
        )
      }
    }

    await client
      .from('publication_items')
      .update({
        resolution_status: 'winner',
        confirmation_code: linked.identity.confirmation_code,
        winner_reply_meta_id: replyId,
        winner_reply_kind: replyKind,
        winner_replied_at: replyId ? new Date().toISOString() : null,
      })
      .eq('id', item.id)

    const conversation = await conversationForIdentity(
      client,
      publication.owner_id,
      publication.page_id,
      linked.customer.id,
      linked.identity.messenger_eligible_until,
      psid,
    )
    const { data: batch, error: batchError } = await client
      .from('winner_notification_batches')
      .upsert({
        owner_id: publication.owner_id,
        publication_id: publication.id,
        customer_id: linked.customer.id,
        conversation_id: canMessage ? conversation?.id : null,
        order_id: order.id,
        status: canMessage ? 'pending' : 'skipped',
        commenter_id: linked.identity.commenter_id,
        confirmation_code: linked.identity.confirmation_code,
        messenger_psid: psid ?? null,
      }, { onConflict: 'publication_id,customer_id' })
      .select()
      .single()
    if (batchError) throw batchError
    batchIds.add(batch.id)
    await client.from('winner_notification_media').upsert({
      batch_id: batch.id,
      order_item_id: orderItem.id,
      position: item.position,
      status: canMessage ? 'pending' : 'failed',
    }, { onConflict: 'batch_id,order_item_id' })
  }

  for (const batchId of batchIds) {
    const { data: media } = await client
      .from('winner_notification_media')
      .select('order_items(price)')
      .eq('batch_id', batchId)
    const subtotal = (media ?? []).reduce(
      (sum, entry) => sum + Number(entry.order_items?.price ?? 0),
      0,
    )
    await client
      .from('winner_notification_batches')
      .update({ item_count: media?.length ?? 0, subtotal })
      .eq('id', batchId)
    await sendWinnerBatch(client, batchId)
  }

  await client
    .from('publications')
    .update({ status: needsReview ? 'review' : 'ended', last_error: null })
    .eq('id', publicationId)
}

async function removeFacebook(client: Client, publicationId: string, ownerId: string) {
  const { data: publication } = await client
    .from('publications')
    .select()
    .eq('id', publicationId)
    .eq('owner_id', ownerId)
    .single()
  if (!publication?.meta_post_id) throw new Error('La publicaciÃ³n no existe en Facebook')
  const token = await pageToken(client, publication.page_id)
  await graph(publication.meta_post_id, token, { method: 'DELETE' })
  await client
    .from('publications')
    .update({ status: 'archived', archived_at: new Date().toISOString() })
    .eq('id', publicationId)
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const client = adminClient()
  try {
    const body = await req.json().catch(() => ({}))
    const cron = await verifyCron(req, client)
    let userId: string | null = null
    if (!cron) userId = (await authenticatedUser(req)).id

    if (body.action === 'delete') {
      await removeFacebook(client, body.publication_id, userId!)
      return response({ ok: true })
    }

    if (body.action === 'sync') {
      if (body.publication_id) {
        const { data: publication } = await client
          .from('publications')
          .select('owner_id')
          .eq('id', body.publication_id)
          .single()
        if (!cron && publication?.owner_id !== userId) return response({ error: 'No autorizado' }, 403)
        await syncAuction(client, body.publication_id)
        return response({ ok: true })
      }
      if (!userId) return response({ error: 'Solicitud invÃ¡lida' }, 400)
      const { data: active } = await client
        .from('publications')
        .select('id')
        .eq('owner_id', userId)
        .eq('publication_type', 'auction')
        .in('status', ['active', 'ended', 'review'])
      for (const publication of active ?? []) await syncAuction(client, publication.id)
      return response({ ok: true, synced: active?.length ?? 0 })
    }

    if (body.publication_id) {
      const { data: publication } = await client
        .from('publications')
        .select('owner_id')
        .eq('id', body.publication_id)
        .single()
      if (!cron && publication?.owner_id !== userId) return response({ error: 'No autorizado' }, 403)
      if (body.action === 'close') await closeAuction(client, body.publication_id)
      else if (body.action === 'remind') await remindAuction(client, body.publication_id, Boolean(body.force))
      else await publishAuction(client, body.publication_id)
      return response({ ok: true })
    }

    if (!cron) return response({ error: 'Solicitud invÃ¡lida' }, 400)
    const { data: jobs } = await client
      .from('automation_jobs')
      .select()
      .eq('status', 'pending')
      .lte('run_at', new Date().toISOString())
      .order('run_at')
      .limit(10)
    for (const job of jobs ?? []) {
      const { data: claimed } = await client
        .from('automation_jobs')
        .update({
          status: 'running',
          locked_at: new Date().toISOString(),
          attempts: job.attempts + 1,
        })
        .eq('id', job.id)
        .eq('status', 'pending')
        .select()
        .maybeSingle()
      if (!claimed) continue
      try {
        if (job.kind === 'publish_auction') await publishAuction(client, job.entity_id)
        if (job.kind === 'close_auction') await closeAuction(client, job.entity_id)
        if (job.kind === 'winner_notification') await sendWinnerBatch(client, job.entity_id)
        await client
          .from('automation_jobs')
          .update({
            status: 'completed',
            completed_at: new Date().toISOString(),
            last_error: null,
          })
          .eq('id', job.id)
      } catch (error) {
        const retry = job.attempts + 1 < 5
        await client
          .from('automation_jobs')
          .update({
            status: retry ? 'pending' : 'failed',
            run_at: new Date(Date.now() + Math.min(60, 2 ** job.attempts) * 60_000)
              .toISOString(),
            last_error: error.message ?? String(error),
          })
          .eq('id', job.id)
        if (!retry) {
          await alert(
            client,
            job.owner_id,
            'error',
            'automation_failed',
            'FallÃ³ una automatizaciÃ³n',
            error.message ?? String(error),
            job.entity_id,
          )
        }
      }
    }
    return response({ processed: jobs?.length ?? 0 })
  } catch (error) {
    if (error instanceof Response) return error
    return response({
      error: error.message ?? String(error),
      code: error.code ?? 'automation_failed',
      type: error.type ?? 'AutomationError',
      details: error.error_subcode ? { subcode: error.error_subcode } : undefined,
    }, 500)
  }
})

