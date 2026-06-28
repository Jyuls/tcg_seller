import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/app_models.dart';

enum AuctionSaveMode { scheduled, publishNow }

class AuctionSaveException implements Exception {
  final String publicationId;
  final Object cause;
  const AuctionSaveException(this.publicationId, this.cause);
  @override
  String toString() => cause.toString();
}

class AppRepository {
  final SupabaseClient client;
  const AppRepository(this.client);

  User get requireUser {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('No hay una sesiÃ³n activa.');
    return user;
  }

  Future<void> signInWithFacebook() async {
    await client.auth.signInWithOAuth(
      OAuthProvider.facebook,
      scopes:
          'public_profile,pages_show_list,pages_read_engagement,pages_read_user_content,pages_manage_posts,pages_manage_engagement,pages_manage_metadata',
      queryParams: const {
        'config_id': '991385223863398',
        'auth_type': 'rerequest',
        'override_default_response_type': 'true',
      },
      authScreenLaunchMode: LaunchMode.inAppBrowserView,
    );
  }

  Future<void> signOut() => client.auth.signOut();

  Future<Map<String, dynamic>> disconnectMeta() async {
    final result = await client.functions.invoke('meta-disconnect');
    final data = Map<String, dynamic>.from(result.data as Map);
    await client.auth.signOut();
    return data;
  }

  Future<void> connectMeta() async {
    final token = client.auth.currentSession?.providerToken;
    if (token == null || token.isEmpty) {
      throw StateError(
        'La autorizaciÃ³n de Meta expirÃ³. Cierra sesiÃ³n e inicia nuevamente.',
      );
    }
    await client.functions.invoke(
      'meta-connect',
      body: {'access_token': token},
    );
  }

  Future<List<FacebookPage>> getPages({bool refreshMeta = false}) async {
    if (refreshMeta) {
      await connectMeta();
    }
    final rows = await client.from('facebook_pages').select().order('name');
    return (rows as List)
        .map((row) => FacebookPage.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> selectPage(String pageId) async {
    final userId = requireUser.id;
    await client
        .from('facebook_pages')
        .update({'is_selected': false})
        .eq('owner_id', userId);
    await client
        .from('facebook_pages')
        .update({'is_selected': true})
        .eq('id', pageId)
        .eq('owner_id', userId);
  }

  Future<FacebookPage?> selectedPage() async {
    final row = await client
        .from('facebook_pages')
        .select()
        .eq('is_selected', true)
        .maybeSingle();
    return row == null ? null : FacebookPage.fromJson(row);
  }

  Future<List<AuctionPublication>> getPublications({
    String? query,
    String? status,
  }) async {
    var request = client
        .from('publications')
        .select(
          '*, publication_items(*, meta_comments!publication_items_winning_comment_fk(author_name,message))',
        )
        .eq('publication_type', 'auction')
        .order('created_at', ascending: false);
    final rows = await request;
    var result = (rows as List)
        .map((row) => AuctionPublication.fromJson(row as Map<String, dynamic>))
        .toList();
    if (status != null && status != 'all') {
      result = result.where((item) => item.status.name == status).toList();
    }
    if (query != null && query.trim().isNotEmpty) {
      final term = query.toLowerCase();
      result = result
          .where(
            (item) =>
                item.title.toLowerCase().contains(term) ||
                item.body.toLowerCase().contains(term),
          )
          .toList();
    }
    return result;
  }

  Future<void> refreshPublicationsFromMeta() async {
    await client.functions.invoke('sync-auction-bids', body: const {});
  }

  Future<void> refreshPublicationFromMeta(String publicationId) async {
    await client.functions.invoke(
      'sync-auction-bids',
      body: {'publication_id': publicationId},
    );
  }

  Future<AuctionPublication> getPublication(String id) async {
    final row = await client
        .from('publications')
        .select(
          '*, publication_items(*, meta_comments!publication_items_winning_comment_fk(author_name,message))',
        )
        .eq('id', id)
        .single();
    return AuctionPublication.fromJson(row);
  }

  Future<String> createAuction({
    String? publicationId,
    required FacebookPage page,
    required List<File> images,
    required String body,
    required DateTime startsAt,
    required DateTime endsAt,
    required int startingBid,
    required int bidIncrement,
    required AuctionSaveMode mode,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (images.isEmpty) {
      throw ArgumentError('La subasta necesita al menos una foto.');
    }
    if (!endsAt.isAfter(startsAt)) {
      throw ArgumentError('La finalizaciÃ³n debe ser posterior al inicio.');
    }
    final ownerId = requireUser.id;
    final id = publicationId ?? const Uuid().v4();
    final scheduledFor = mode == AuctionSaveMode.publishNow
        ? DateTime.now().toUtc()
        : startsAt.toUtc();
    final publicationData = {
      'id': id,
      'owner_id': ownerId,
      'page_id': page.id,
      'title': 'Subasta',
      'body': body,
      'publication_type': 'auction',
      'status': 'draft',
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'scheduled_for': scheduledFor.toIso8601String(),
      'starting_bid': startingBid,
      'bid_increment': bidIncrement,
      'last_error': null,
    };
    if (publicationId == null) {
      await client.from('publications').insert(publicationData);
    } else {
      await client
          .from('publications')
          .update(publicationData..remove('id'))
          .eq('id', id);
    }
    try {
      for (var index = 0; index < images.length; index++) {
        final extension = images[index].path.toLowerCase().endsWith('.png')
            ? 'png'
            : 'jpg';
        final path =
            '$ownerId/$id/${index.toString().padLeft(3, '0')}.$extension';
        await client.from('publication_items').upsert({
          'publication_id': id,
          'position': index,
          'storage_path': path,
          'upload_status': 'pending',
        }, onConflict: 'publication_id,position');
        await client.storage
            .from('auction-media')
            .upload(
              path,
              images[index],
              fileOptions: const FileOptions(upsert: true),
            );
        await client
            .from('publication_items')
            .update({'upload_status': 'uploaded'})
            .eq('publication_id', id)
            .eq('position', index);
        if (index == 0) {
          await client
              .from('publications')
              .update({'cover_storage_path': path})
              .eq('id', id);
        }
        onProgress?.call(index + 1, images.length);
      }
      final status = switch (mode) {
        AuctionSaveMode.scheduled => 'scheduled',
        AuctionSaveMode.publishNow => 'publishing',
      };
      await client
          .from('publications')
          .update({
            'status': status,
            'scheduled_for': scheduledFor.toIso8601String(),
            'last_error': null,
          })
          .eq('id', id);
      await client.from('automation_jobs').upsert({
        'owner_id': ownerId,
        'kind': 'publish_auction',
        'entity_id': id,
        'run_at': scheduledFor.toIso8601String(),
        'status': 'pending',
        'attempts': 0,
        'last_error': null,
        'idempotency_key': 'publish:$id',
      }, onConflict: 'idempotency_key');
      if (mode == AuctionSaveMode.publishNow) {
        await client.functions.invoke(
          'automation-worker',
          body: {'publication_id': id, 'action': 'publish'},
        );
      }
      return id;
    } catch (error) {
      await client
          .from('publications')
          .update({'status': 'failed', 'last_error': error.toString()})
          .eq('id', id);
      throw AuctionSaveException(id, error);
    }
  }

  Future<String> signedImageUrl(String path) async {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return client.storage.from('auction-media').createSignedUrl(path, 3600);
  }

  Future<void> archivePublication(String id) => client
      .from('publications')
      .update({
        'status': 'archived',
        'archived_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', id);
  Future<void> deleteFromFacebook(String id) async => client.functions.invoke(
    'automation-worker',
    body: {'publication_id': id, 'action': 'delete'},
  );
  Future<void> retryMetaPublication(String id) async {
    await client
        .from('publications')
        .update({'status': 'publishing', 'last_error': null})
        .eq('id', id);
    await client.functions.invoke(
      'automation-worker',
      body: {'publication_id': id, 'action': 'publish'},
    );
  }

  Future<void> remindAuction(String id, {bool force = false}) async {
    await client.functions.invoke(
      'automation-worker',
      body: {'publication_id': id, 'action': 'remind', 'force': force},
    );
  }

  Future<List<Customer>> getCustomers() async {
    final rows = await client
        .from('customers')
        .select('*, delivery_locations(*)')
        .order('display_name');
    return (rows as List)
        .map((row) => Customer.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveCustomer({
    String? id,
    required FacebookPage page,
    required String name,
    required String category,
    required String notes,
    File? picture,
    String? preferredDeliveryLocationId,
    String preferredDeliveryMode = 'general',
    String? preferredFixedBoothName,
    int? preferredDeliveryZone,
    int? preferredBoothNumber,
    String preferredDeliveryNotes = '',
  }) async {
    final customerId = id ?? const Uuid().v4();
    final data = {
      'id': customerId,
      'owner_id': requireUser.id,
      'page_id': page.id,
      'display_name': name.trim(),
      'category': category,
      'notes': notes.trim(),
      'is_provisional': false,
      'preferred_delivery_location_id': preferredDeliveryLocationId,
      'preferred_delivery_mode': preferredDeliveryMode,
      'preferred_fixed_booth_name': preferredFixedBoothName?.trim(),
      'preferred_delivery_zone': preferredDeliveryZone,
      'preferred_booth_number': preferredBoothNumber,
      'preferred_delivery_notes': preferredDeliveryNotes.trim(),
    };
    if (picture != null) {
      final extension = picture.path.toLowerCase().endsWith('.png')
          ? 'png'
          : 'jpg';
      final path = '${requireUser.id}/customers/$customerId.$extension';
      await client.storage
          .from('customer-media')
          .upload(path, picture, fileOptions: const FileOptions(upsert: true));
      data['picture_storage_path'] = path;
    }
    if (id == null) {
      await client.from('customers').insert(data);
    } else {
      await client.from('customers').update(data..remove('id')).eq('id', id);
    }
  }

  Future<String> signedCustomerImageUrl(String path) =>
      client.storage.from('customer-media').createSignedUrl(path, 3600);

  Future<List<OrderSummary>> getOrders() async {
    final rows = await client
        .from('orders')
        .select(
          '*, customers(display_name), delivery_locations(name,location_help_text), order_items(*)',
        )
        .order('created_at', ascending: false);
    final result = (rows as List)
        .map((row) => OrderSummary.fromJson(row as Map<String, dynamic>))
        .toList();
    result.sort((a, b) {
      int rank(OrderSummary order) => order.deliveryStatus == 'delivered'
          ? 2
          : order.deliveryStatus == 'cancelled'
          ? 3
          : order.paymentStatus == 'paid'
          ? 0
          : 1;
      final rankCompare = rank(a).compareTo(rank(b));
      if (rankCompare != 0) return rankCompare;
      final packingA = a.packingPosition ?? 1 << 30;
      final packingB = b.packingPosition ?? 1 << 30;
      final packingCompare = packingA.compareTo(packingB);
      if (packingCompare != 0) return packingCompare;
      return b.id.compareTo(a.id);
    });
    return result;
  }

  Future<void> markOrderPaid(String id) => client
      .from('orders')
      .update({
        'payment_status': 'paid',
        'paid_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', id);
  Future<void> markOrderDelivered(String id) =>
      client.rpc('mark_order_delivered', params: {'target_order_id': id});
  Future<void> cancelOrder(String id) => client
      .from('orders')
      .update({
        'delivery_status': 'cancelled',
        'cancelled_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', id);

  Future<void> removeOrderItem(Map<String, dynamic> item) async {
    final itemId = item['id'] as String?;
    if (itemId == null) throw StateError('El artÃ­culo no tiene ID.');
    final publicationItemId = item['publication_item_id'] as String?;
    await client.from('order_items').delete().eq('id', itemId);
    if (publicationItemId != null && publicationItemId.isNotEmpty) {
      await client
          .from('publication_items')
          .update({'resolution_status': 'review'})
          .eq('id', publicationItemId);
    }
  }

  Future<void> packOrderNext(String id) async {
    final page = await selectedPage();
    if (page == null) throw StateError('Selecciona una pÃ¡gina primero.');
    final rows = await client
        .from('orders')
        .select('packing_position')
        .eq('page_id', page.id)
        .eq('delivery_status', 'pending')
        .not('packing_position', 'is', null)
        .order('packing_position', ascending: false)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows as List);
    final last = list.isEmpty ? 0 : list.first['packing_position'] as int? ?? 0;
    await client
        .from('orders')
        .update({
          'packing_position': last + 1,
          'packed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }

  Future<void> unpackOrder(String id) => client
      .from('orders')
      .update({'packing_position': null, 'packed_at': null})
      .eq('id', id);

  Future<Map<String, dynamic>> sendOrderConfirmation(OrderSummary order) async {
    final conversation = await client
        .from('conversations')
        .select('id')
        .eq('customer_id', order.customerId)
        .order('last_message_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (conversation == null) {
      throw StateError('Este cliente no tiene conversaciÃ³n de Messenger.');
    }
    final photoPaths = order.items
        .map((item) => item['photo_storage_path'])
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .toList();
    final result = await client.functions.invoke(
      'order-messaging',
      body: {
        'action': 'manual_order_confirmation',
        'conversation_id': conversation['id'] as String,
        'price': order.total,
        'delivery_location_name': order.deliveryLocation,
        'delivery_mode': order.deliveryMode,
        'fixed_booth_name': order.fixedBoothName,
        'zone': order.deliveryZone,
        'booth_number': order.boothNumber,
        'attachment_storage_paths': photoPaths,
        'attachment_storage_path': photoPaths.isEmpty ? null : photoPaths.first,
        'delivery_detail': deliveryDetailText(
          locationName: order.deliveryLocation,
          deliveryMode: order.deliveryMode,
          fixedBoothName: order.fixedBoothName,
          zone: order.deliveryZone,
          boothNumber: order.boothNumber,
          notes: order.deliveryNotes,
          helpText: order.locationHelpText,
        ),
      },
    );
    final data = result.data;
    if (data is Map && data['sent'] == false) {
      final reason = data['reason']?.toString();
      if (reason == 'closed_window') {
        throw StateError(
          'La ventana de Messenger estÃ¡ cerrada. El cliente debe enviar un mensaje primero.',
        );
      }
      throw StateError(
        reason ??
            data['error']?.toString() ??
            'Meta no permitiÃ³ enviar el mensaje.',
      );
    }
    if (data is Map && data['ok'] == false) {
      throw StateError(
        data['error']?.toString() ?? 'No se pudo enviar la confirmaciÃ³n.',
      );
    }
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<void> updateOrderDelivery({
    required String orderId,
    String? deliveryLocationId,
    String deliveryMode = 'general',
    String? fixedBoothName,
    int? zone,
    int? boothNumber,
    String locationHelpText = '',
    String notes = '',
  }) => client
      .from('orders')
      .update({
        'delivery_location_id': deliveryLocationId,
        'delivery_mode': deliveryMode,
        'fixed_booth_name': fixedBoothName?.trim(),
        'delivery_zone': zone,
        'booth_number': boothNumber,
        'location_help_text': locationHelpText.trim(),
        'delivery_notes': notes.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', orderId);

  Future<void> createManualOrderItem({
    required FacebookPage page,
    required Customer customer,
    File? image,
    required String sourceLabel,
    required int price,
    String? deliveryLocationId,
    String deliveryMode = 'general',
    String? fixedBoothName,
    int? deliveryZone,
    int? boothNumber,
    String locationHelpText = '',
    String deliveryNotes = '',
  }) async {
    final ownerId = requireUser.id;
    final existing = await client
        .from('orders')
        .select('id')
        .eq('customer_id', customer.id)
        .eq('payment_status', 'pending')
        .eq('delivery_status', 'pending')
        .maybeSingle();
    String orderId;
    if (existing == null) {
      final row = await client
          .from('orders')
          .insert({
            'owner_id': ownerId,
            'page_id': page.id,
            'customer_id': customer.id,
            'delivery_location_id': deliveryLocationId,
            'delivery_mode': deliveryMode,
            'fixed_booth_name': fixedBoothName?.trim(),
            'delivery_zone': deliveryZone,
            'booth_number': boothNumber,
            'location_help_text': locationHelpText.trim(),
            'delivery_notes': deliveryNotes.trim(),
          })
          .select('id')
          .single();
      orderId = row['id'] as String;
    } else {
      orderId = existing['id'] as String;
      await updateOrderDelivery(
        orderId: orderId,
        deliveryLocationId: deliveryLocationId,
        deliveryMode: deliveryMode,
        fixedBoothName: fixedBoothName,
        zone: deliveryZone,
        boothNumber: boothNumber,
        locationHelpText: locationHelpText,
        notes: deliveryNotes,
      );
    }
    String? path;
    if (image != null) {
      final extension = image.path.toLowerCase().endsWith('.png')
          ? 'png'
          : 'jpg';
      path = '$ownerId/manual-orders/$orderId/${const Uuid().v4()}.$extension';
      await client.storage.from('auction-media').upload(path, image);
    }
    await client.from('order_items').insert({
      'order_id': orderId,
      'photo_storage_path': path,
      'source_label': sourceLabel.trim(),
      'price': price,
    });
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    final conversations = List<Map<String, dynamic>>.from(
      await client
          .from('conversations')
          .select('*, customers(display_name,picture_url)')
          .order('last_message_at', ascending: false),
    );
    for (final conversation in conversations) {
      final latest = await client
          .from('messages')
          .select('body,direction,meta_created_at,created_at')
          .eq('conversation_id', conversation['id'] as String)
          .order('meta_created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      conversation['latest_message'] = latest;
    }
    return conversations;
  }

  Future<void> syncMessagesFromMeta() async {
    final response = await client.functions.invoke('meta-sync-messages');
    final data = response.data;
    if (data is Map && data['meta_permission_denied'] == true) {
      throw StateError(
        'Meta aÃºn no permite leer Messenger; se mostrarÃ¡n mensajes recibidos por webhook o pruebas locales.',
      );
    }
  }

  Future<Map<String, dynamic>> testMessengerCode(String code) async {
    final result = await client.functions.invoke(
      'test-messenger-code',
      body: {'code': code.trim().toUpperCase()},
    );
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<List<Map<String, dynamic>>> getMessages(String conversationId) async =>
      (List<Map<String, dynamic>>.from(
        await client
            .from('messages')
            .select()
            .eq('conversation_id', conversationId),
      )..sort((a, b) {
        final aTime = DateTime.tryParse(
          (a['meta_created_at'] ?? a['created_at'] ?? '') as String,
        );
        final bTime = DateTime.tryParse(
          (b['meta_created_at'] ?? b['created_at'] ?? '') as String,
        );
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return aTime.compareTo(bTime);
      }));

  Future<void> markConversationRead(String conversationId) async {
    await client
        .from('conversations')
        .update({'unread_count': 0})
        .eq('id', conversationId);
  }

  Future<void> sendMessage(String conversationId, String body) async =>
      client.functions.invoke(
        'messenger-send',
        body: {'conversation_id': conversationId, 'message': body.trim()},
      );

  Future<void> createManualOrderFromConversation({
    required String conversationId,
    File? image,
    required String sourceLabel,
    required int price,
    String? deliveryLocationId,
    String deliveryMode = 'general',
    String? fixedBoothName,
    int? deliveryZone,
    int? boothNumber,
    String locationHelpText = '',
    String deliveryNotes = '',
  }) async {
    final page = await selectedPage();
    if (page == null) throw StateError('Selecciona una pÃ¡gina primero.');
    final conversation = await client
        .from('conversations')
        .select('*, customers(*)')
        .eq('id', conversationId)
        .single();
    final customerData = conversation['customers'] as Map<String, dynamic>?;
    if (customerData == null) {
      throw StateError(
        'Esta conversaciÃ³n todavÃ­a no estÃ¡ vinculada a un cliente.',
      );
    }
    await createManualOrderItem(
      page: page,
      customer: Customer.fromJson(customerData),
      image: image,
      sourceLabel: sourceLabel,
      price: price,
      deliveryLocationId: deliveryLocationId,
      deliveryMode: deliveryMode,
      fixedBoothName: fixedBoothName,
      deliveryZone: deliveryZone,
      boothNumber: boothNumber,
      locationHelpText: locationHelpText,
      deliveryNotes: deliveryNotes,
    );
    String? attachmentPath;
    if (image != null) {
      final ownerId = requireUser.id;
      final extension = image.path.toLowerCase().endsWith('.png')
          ? 'png'
          : 'jpg';
      attachmentPath =
          '$ownerId/chat-order-confirmations/${const Uuid().v4()}.$extension';
      await client.storage.from('auction-media').upload(attachmentPath, image);
    }
    String? locationName;
    if (deliveryLocationId != null) {
      final row = await client
          .from('delivery_locations')
          .select('name')
          .eq('id', deliveryLocationId)
          .maybeSingle();
      locationName = row?['name'] as String?;
    }
    await client.functions.invoke(
      'order-messaging',
      body: {
        'action': 'manual_order_confirmation',
        'conversation_id': conversationId,
        'price': price,
        'delivery_location_name': locationName,
        'delivery_mode': deliveryMode,
        'fixed_booth_name': fixedBoothName,
        'zone': deliveryZone,
        'booth_number': boothNumber,
        'attachment_storage_path': attachmentPath,
        'delivery_detail': deliveryDetailText(
          locationName: locationName,
          deliveryMode: deliveryMode,
          fixedBoothName: fixedBoothName,
          zone: deliveryZone,
          boothNumber: boothNumber,
          notes: deliveryNotes,
          helpText: locationHelpText,
        ),
      },
    );
  }

  Future<List<Map<String, dynamic>>> getClaimableAuctionItems() async {
    final rows = await client
        .from('publication_items')
        .select(
          'id,position,storage_path,winning_amount,resolution_status, publications!inner(id,title,ends_at,status,publication_type), order_items(id)',
        )
        .not('winning_amount', 'is', null)
        .eq('publications.publication_type', 'auction')
        .inFilter('publications.status', ['ended', 'review'])
        .order('position');
    final result = List<Map<String, dynamic>>.from(rows as List);
    result.removeWhere((row) {
      final status = row['resolution_status'] as String? ?? '';
      if (status == 'discarded' || status == 'ignored') return true;
      final orderItems = row['order_items'];
      return orderItems is List && orderItems.isNotEmpty;
    });
    result.sort((a, b) {
      final publicationA = a['publications'] as Map<String, dynamic>;
      final publicationB = b['publications'] as Map<String, dynamic>;
      final dateA = DateTime.tryParse(publicationA['ends_at'] as String? ?? '');
      final dateB = DateTime.tryParse(publicationB['ends_at'] as String? ?? '');
      final dateCompare = (dateB ?? DateTime(0)).compareTo(
        dateA ?? DateTime(0),
      );
      if (dateCompare != 0) return dateCompare;
      return (a['position'] as int? ?? 0).compareTo(b['position'] as int? ?? 0);
    });
    return result;
  }

  Future<void> discardRemainingClaimableItems(String publicationId) async {
    final rows = await getClaimableAuctionItems();
    final ids = rows
        .where((item) {
          final publication = item['publications'] as Map<String, dynamic>;
          return publication['id'] == publicationId;
        })
        .map((item) => item['id'] as String)
        .toList();
    if (ids.isEmpty) return;
    await client
        .from('publication_items')
        .update({'resolution_status': 'discarded'})
        .inFilter('id', ids);
  }

  Future<void> createOrderFromClaimedAuctionItems({
    required String conversationId,
    required List<Map<String, dynamic>> items,
    String? deliveryLocationId,
    String deliveryMode = 'general',
    String? fixedBoothName,
    int? deliveryZone,
    int? boothNumber,
    String locationHelpText = '',
    String deliveryNotes = '',
  }) async {
    if (items.isEmpty) throw ArgumentError('Selecciona al menos un artÃ­culo.');
    final page = await selectedPage();
    if (page == null) throw StateError('Selecciona una pÃ¡gina primero.');
    final conversation = await client
        .from('conversations')
        .select('*, customers(*)')
        .eq('id', conversationId)
        .single();
    final customerData = conversation['customers'] as Map<String, dynamic>?;
    if (customerData == null) {
      throw StateError(
        'Esta conversaciÃ³n todavÃ­a no estÃ¡ vinculada a un cliente.',
      );
    }
    final customer = Customer.fromJson(customerData);
    final existing = await client
        .from('orders')
        .select('id')
        .eq('customer_id', customer.id)
        .eq('payment_status', 'pending')
        .eq('delivery_status', 'pending')
        .maybeSingle();
    String orderId;
    if (existing == null) {
      final row = await client
          .from('orders')
          .insert({
            'owner_id': requireUser.id,
            'page_id': page.id,
            'customer_id': customer.id,
            'delivery_location_id': deliveryLocationId,
            'delivery_mode': deliveryMode,
            'fixed_booth_name': fixedBoothName?.trim(),
            'delivery_zone': deliveryZone,
            'booth_number': boothNumber,
            'location_help_text': locationHelpText.trim(),
            'delivery_notes': deliveryNotes.trim(),
          })
          .select('id')
          .single();
      orderId = row['id'] as String;
    } else {
      orderId = existing['id'] as String;
      await updateOrderDelivery(
        orderId: orderId,
        deliveryLocationId: deliveryLocationId,
        deliveryMode: deliveryMode,
        fixedBoothName: fixedBoothName,
        zone: deliveryZone,
        boothNumber: boothNumber,
        locationHelpText: locationHelpText,
        notes: deliveryNotes,
      );
    }

    for (final item in items) {
      final publication = item['publications'] as Map<String, dynamic>;
      final position = item['position'] as int? ?? 0;
      final price = item['winning_amount'] as int? ?? 0;
      await client.from('order_items').upsert({
        'order_id': orderId,
        'publication_item_id': item['id'] as String,
        'photo_storage_path': item['storage_path'] as String?,
        'source_label':
            '${publication['title'] ?? 'Subasta'} Â· ArtÃ­culo ${position + 1}',
        'price': price,
      }, onConflict: 'publication_item_id');
      await client
          .from('publication_items')
          .update({'resolution_status': 'winner'})
          .eq('id', item['id'] as String);
    }
  }

  Future<void> assignClaimedAuctionItemsToCustomer({
    required String customerId,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) throw ArgumentError('Selecciona al menos un artÃ­culo.');
    final page = await selectedPage();
    if (page == null) throw StateError('Selecciona una pÃ¡gina primero.');
    final customerRow = await client
        .from('customers')
        .select('*, delivery_locations(*)')
        .eq('id', customerId)
        .single();
    final customer = Customer.fromJson(customerRow);
    final existing = await client
        .from('orders')
        .select('id')
        .eq('customer_id', customer.id)
        .eq('payment_status', 'pending')
        .eq('delivery_status', 'pending')
        .maybeSingle();
    String orderId;
    if (existing == null) {
      final row = await client
          .from('orders')
          .insert({
            'owner_id': requireUser.id,
            'page_id': page.id,
            'customer_id': customer.id,
            'delivery_location_id': customer.preferredDeliveryLocationId,
            'delivery_mode': customer.preferredDeliveryMode,
            'fixed_booth_name': customer.preferredFixedBoothName,
            'delivery_zone': customer.preferredDeliveryZone,
            'booth_number': customer.preferredBoothNumber,
            'delivery_notes': customer.preferredDeliveryNotes,
          })
          .select('id')
          .single();
      orderId = row['id'] as String;
    } else {
      orderId = existing['id'] as String;
    }
    for (final item in items) {
      final publication = item['publications'] as Map<String, dynamic>;
      final position = item['position'] as int? ?? 0;
      await client.from('order_items').upsert({
        'order_id': orderId,
        'publication_item_id': item['id'] as String,
        'photo_storage_path': item['storage_path'] as String?,
        'source_label':
            '${publication['title'] ?? 'Subasta'} Â· ArtÃ­culo ${position + 1}',
        'price': item['winning_amount'] as int? ?? 0,
      }, onConflict: 'publication_item_id');
      await client
          .from('publication_items')
          .update({'resolution_status': 'winner'})
          .eq('id', item['id'] as String);
    }
  }

  Future<Map<String, dynamic>> sendBulkOrderMessage({
    required String action,
    String? deliveryLocationId,
    required String deliveryDetail,
    String description = '',
    String until = '',
    File? image,
  }) async {
    String? attachmentPath;
    if (image != null) {
      final ownerId = requireUser.id;
      final extension = image.path.toLowerCase().endsWith('.png')
          ? 'png'
          : 'jpg';
      attachmentPath = '$ownerId/bulk-messages/${const Uuid().v4()}.$extension';
      await client.storage.from('auction-media').upload(attachmentPath, image);
    }
    final result = await client.functions.invoke(
      'order-messaging',
      body: {
        'action': action,
        'delivery_location_id': deliveryLocationId,
        'delivery_detail': deliveryDetail,
        'description': description,
        'until': until,
        'attachment_storage_path': attachmentPath,
      },
    );
    return Map<String, dynamic>.from(result.data as Map);
  }

  String deliveryDetailText({
    String? locationName,
    required String deliveryMode,
    String? fixedBoothName,
    int? zone,
    int? boothNumber,
    String notes = '',
    String helpText = '',
  }) {
    final parts = <String>[
      if (locationName != null && locationName.trim().isNotEmpty)
        locationName.trim(),
      if (deliveryMode == 'fixed_booth' &&
          fixedBoothName != null &&
          fixedBoothName.trim().isNotEmpty)
        'puesto ${fixedBoothName.trim()}',
      if (deliveryMode == 'roaming') 'ambulando',
      if (zone != null) 'zona $zone',
      if (boothNumber != null) 'puesto #$boothNumber',
      if (notes.trim().isNotEmpty) notes.trim(),
      if (helpText.trim().isNotEmpty) helpText.trim(),
    ];
    return parts.isEmpty ? 'por confirmar' : parts.join(' Â· ');
  }

  Future<List<Map<String, dynamic>>> getAlerts() async =>
      List<Map<String, dynamic>>.from(
        await client
            .from('alerts')
            .select()
            .isFilter('read_at', null)
            .order('created_at', ascending: false)
            .limit(20),
      );
  Future<Map<String, dynamic>?> getSettings() async =>
      await client.from('app_settings').select().maybeSingle();
  Future<void> saveSettings(Map<String, dynamic> values) => client
      .from('app_settings')
      .upsert({'owner_id': requireUser.id, ...values});
  Future<List<Map<String, dynamic>>> getMessageTemplates() async =>
      List<Map<String, dynamic>>.from(
        await client.from('message_templates').select().order('kind'),
      );
  Future<void> saveMessageTemplate(String kind, String body) =>
      client.from('message_templates').upsert({
        'owner_id': requireUser.id,
        'kind': kind,
        'body': body,
      }, onConflict: 'owner_id,kind');
  Future<List<Map<String, dynamic>>> getDeliveryLocations() async =>
      List<Map<String, dynamic>>.from(
        await client.from('delivery_locations').select().order('position'),
      );
  Future<void> saveDeliveryLocation({
    String? id,
    required String name,
    required bool requiresBooth,
    String defaultDeliveryMode = 'general',
    String? defaultFixedBoothName,
    String locationHelpText = '',
    int? defaultZone,
    int? defaultBoothNumber,
  }) async {
    final data = {
      'owner_id': requireUser.id,
      'name': name.trim(),
      'requires_booth': requiresBooth,
      'default_delivery_mode': defaultDeliveryMode,
      'default_fixed_booth_name': defaultFixedBoothName?.trim(),
      'location_help_text': locationHelpText.trim(),
      'default_zone': defaultZone,
      'default_booth_number': defaultBoothNumber,
    };
    if (id == null) {
      await client.from('delivery_locations').insert(data);
    } else {
      await client.from('delivery_locations').update(data).eq('id', id);
    }
  }
}
