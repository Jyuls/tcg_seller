import {
  adminClient,
  authenticatedUser,
  corsHeaders,
  graph,
  pageToken,
  response,
} from '../_shared/core.ts'

type Client = ReturnType<typeof adminClient>

function validAmount(message: string) {
  const match = message.match(/^\s*\$?\s*([0-9]+)\s*$/)
  if (!match) return null
  const amount = Number(match[1])
  return Number.isSafeInteger(amount) ? amount : null
}

function pagePathFromUrl(url: string) {
  return url.replace(/^https:\/\/graph\.facebook\.com\/v[0-9.]+\//, '')
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
  return source
    .map((entry: Record<string, any>) => entry.target?.id)
    .filter(Boolean) as string[]
}

async function allComments(photoId: string, token: string) {
  const rows: Record<string, any>[] = []
  let path =
    `${photoId}/comments?fields=id,message,from{id,name},created_time&limit=100&order=chronological`
  for (let page = 0; path && page < 30; page++) {
    const payload = await graph(path, token)
    rows.push(...(payload.data ?? []))
    const next = payload.paging?.next as string | undefined
    path = next ? pagePathFromUrl(next) : ''
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
  const onGrid =
    amount !== null &&
    amount >= publication.starting_bid &&
    (amount - publication.starting_bid) % publication.bid_increment === 0
  const isValid = amount !== null && beforeClose && onGrid
  const rejection = amount === null
    ? 'format'
    : !beforeClose
    ? 'after_close'
    : !onGrid
    ? 'minimum_bid'
    : null
  const { data: stored, error } = await client
    .from('meta_comments')
    .upsert(
      {
        publication_item_id: item.id,
        meta_comment_id: String(raw.id),
        author_meta_id: raw.from?.id ? String(raw.from.id) : null,
        author_name: raw.from?.name ? String(raw.from.name) : null,
        message: String(raw.message ?? ''),
        meta_created_at: created.toISOString(),
        raw_payload: raw,
      },
      { onConflict: 'meta_comment_id' },
    )
    .select()
    .single()
  if (error) throw error
  if (amount !== null) {
    await client.from('bids').upsert(
      {
        comment_id: stored.id,
        publication_item_id: item.id,
        amount,
        meta_created_at: created.toISOString(),
        is_valid: isValid,
        rejection_reason: rejection,
      },
      { onConflict: 'comment_id' },
    )
  }
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
      resolution_status: 'open',
    })
    .eq('id', itemId)
}

async function syncOne(client: Client, publicationId: string, ownerId: string) {
  const { data: publication, error } = await client
    .from('publications')
    .select('*, facebook_pages(*)')
    .eq('id', publicationId)
    .eq('owner_id', ownerId)
    .single()
  if (error || !publication) throw error ?? new Error('Publicación inexistente')
  if (publication.publication_type && publication.publication_type !== 'auction') {
    return { publication_id: publicationId, comments: 0, items: 0 }
  }
  if (!publication.meta_post_id) {
    return { publication_id: publicationId, comments: 0, items: 0 }
  }

  const token = await pageToken(client, publication.page_id)
  const { data: items } = await client
    .from('publication_items')
    .select()
    .eq('publication_id', publicationId)
    .order('position')

  const ids = await attachmentPhotoIds(publication.meta_post_id, token).catch(
    () => [],
  )
  for (let index = 0; index < (items?.length ?? 0) && index < ids.length; index++) {
    const item = items![index]
    if (ids[index] && item.meta_photo_id !== ids[index]) {
      item.meta_photo_id = ids[index]
      await client
        .from('publication_items')
        .update({ meta_photo_id: ids[index] })
        .eq('id', item.id)
    }
  }

  let totalComments = 0
  for (const item of items ?? []) {
    if (!item.meta_photo_id) continue
    const comments = await allComments(item.meta_photo_id, token)
    totalComments += comments.length
    for (const raw of comments) {
      await storeCommentAndBid(client, publication, item, raw)
    }
    await client
      .from('publication_items')
      .update({ comment_count: comments.length })
      .eq('id', item.id)
    await refreshWinner(client, item.id)
  }

  return {
    publication_id: publicationId,
    items: items?.length ?? 0,
    comments: totalComments,
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const user = await authenticatedUser(req)
    const client = adminClient()
    const body = await req.json().catch(() => ({}))
    if (body.publication_id) {
      return response({
        ok: true,
        result: await syncOne(client, String(body.publication_id), user.id),
      })
    }
    const { data: publications, error } = await client
      .from('publications')
      .select('id')
      .eq('owner_id', user.id)
      .eq('publication_type', 'auction')
      .in('status', ['active', 'ended', 'review'])
      .order('created_at', { ascending: false })
      .limit(20)
    if (error) throw error
    const results = []
    for (const publication of publications ?? []) {
      results.push(await syncOne(client, publication.id, user.id))
    }
    return response({ ok: true, results })
  } catch (error) {
    if (error instanceof Response) return error
    return response({ ok: false, error: error.message ?? String(error) }, 500)
  }
})
