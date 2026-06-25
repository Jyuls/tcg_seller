enum PublicationStatus {
  draft,
  scheduled,
  publishing,
  active,
  ended,
  review,
  failed,
  archived,
}

class FacebookPage {
  final String id;
  final String metaPageId;
  final String name;
  final String? pictureUrl;
  final bool isSelected;

  const FacebookPage({
    required this.id,
    required this.metaPageId,
    required this.name,
    this.pictureUrl,
    required this.isSelected,
  });

  factory FacebookPage.fromJson(Map<String, dynamic> json) => FacebookPage(
    id: json['id'] as String,
    metaPageId: json['meta_page_id'] as String,
    name: json['name'] as String,
    pictureUrl: json['picture_url'] as String?,
    isSelected: json['is_selected'] as bool? ?? false,
  );
}

class AuctionPublication {
  final String id;
  final String title;
  final String body;
  final PublicationStatus status;
  final DateTime startsAt;
  final DateTime endsAt;
  final int startingBid;
  final int bidIncrement;
  final String? coverPath;
  final String? metaPostId;
  final String publicationType;
  final String? error;
  final List<AuctionItem> items;

  const AuctionPublication({
    required this.id,
    required this.title,
    required this.body,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.startingBid,
    required this.bidIncrement,
    this.coverPath,
    this.metaPostId,
    this.publicationType = 'auction',
    this.error,
    this.items = const [],
  });

  int get total =>
      items.fold(0, (sum, item) => sum + (item.winningAmount ?? 0));
  bool get isAuction => publicationType == 'auction';
  bool get isNormal => publicationType == 'normal';
  int get commentCount => items.fold(0, (sum, item) => sum + item.commentCount);

  factory AuctionPublication.fromJson(Map<String, dynamic> json) {
    final rawItems =
        json['publication_items_with_counts'] as List<dynamic>? ??
        json['publication_items'] as List<dynamic>? ??
        const [];
    return AuctionPublication(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Subasta',
      body: json['body'] as String? ?? '',
      status: PublicationStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => PublicationStatus.draft,
      ),
      startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
      endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
      startingBid: json['starting_bid'] as int? ?? 5,
      bidIncrement: json['bid_increment'] as int? ?? 5,
      coverPath: json['cover_storage_path'] as String?,
      metaPostId: json['meta_post_id'] as String?,
      publicationType: json['publication_type'] as String? ?? 'auction',
      error: json['last_error'] as String?,
      items:
          rawItems
              .map((item) => AuctionItem.fromJson(item as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => a.position.compareTo(b.position)),
    );
  }
}

class AuctionItem {
  final String id;
  final int position;
  final String storagePath;
  final int? winningAmount;
  final String resolutionStatus;
  final String uploadStatus;
  final String? winningAuthor;
  final String? winningMessage;
  final int commentCount;
  final int reminderCount;
  final DateTime? reminderSentAt;

  const AuctionItem({
    required this.id,
    required this.position,
    required this.storagePath,
    this.winningAmount,
    required this.resolutionStatus,
    required this.uploadStatus,
    this.winningAuthor,
    this.winningMessage,
    this.commentCount = 0,
    this.reminderCount = 0,
    this.reminderSentAt,
  });

  factory AuctionItem.fromJson(Map<String, dynamic> json) {
    final comment = json['meta_comments'] is Map<String, dynamic>
        ? json['meta_comments'] as Map<String, dynamic>
        : null;
    return AuctionItem(
      id: json['id'] as String,
      position: json['position'] as int? ?? 0,
      storagePath: json['storage_path'] as String,
      winningAmount: json['winning_amount'] as int?,
      resolutionStatus: json['resolution_status'] as String? ?? 'open',
      uploadStatus: json['upload_status'] as String? ?? 'pending',
      winningAuthor: comment?['author_name'] as String?,
      winningMessage: comment?['message'] as String?,
      commentCount: json['comment_count'] as int? ?? 0,
      reminderCount: json['reminder_count'] as int? ?? 0,
      reminderSentAt: json['reminder_sent_at'] == null
          ? null
          : DateTime.parse(json['reminder_sent_at'] as String).toLocal(),
    );
  }
}

class Customer {
  final String id;
  final String name;
  final String? pictureUrl;
  final String? pictureStoragePath;
  final String category;
  final String notes;
  final bool provisional;
  final String? preferredDeliveryLocationId;
  final String? preferredDeliveryLocation;
  final String preferredDeliveryMode;
  final String? preferredFixedBoothName;
  final int? preferredDeliveryZone;
  final int? preferredBoothNumber;
  final String preferredDeliveryNotes;

  const Customer({
    required this.id,
    required this.name,
    this.pictureUrl,
    this.pictureStoragePath,
    required this.category,
    required this.notes,
    required this.provisional,
    this.preferredDeliveryLocationId,
    this.preferredDeliveryLocation,
    this.preferredDeliveryMode = 'general',
    this.preferredFixedBoothName,
    this.preferredDeliveryZone,
    this.preferredBoothNumber,
    this.preferredDeliveryNotes = '',
  });
  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id'] as String,
    name: json['display_name'] as String,
    pictureUrl: json['picture_url'] as String?,
    pictureStoragePath: json['picture_storage_path'] as String?,
    category: json['category'] as String? ?? 'unclassified',
    notes: json['notes'] as String? ?? '',
    provisional: json['is_provisional'] as bool? ?? false,
    preferredDeliveryLocationId:
        json['preferred_delivery_location_id'] as String?,
    preferredDeliveryLocation:
        (json['delivery_locations'] as Map<String, dynamic>?)?['name']
            as String?,
    preferredDeliveryMode:
        json['preferred_delivery_mode'] as String? ?? 'general',
    preferredFixedBoothName: json['preferred_fixed_booth_name'] as String?,
    preferredDeliveryZone: json['preferred_delivery_zone'] as int?,
    preferredBoothNumber: json['preferred_booth_number'] as int?,
    preferredDeliveryNotes: json['preferred_delivery_notes'] as String? ?? '',
  );
}

class OrderSummary {
  final String id;
  final String customerId;
  final String customerName;
  final int total;
  final String paymentStatus;
  final String deliveryStatus;
  final String? deliveryLocation;
  final String? deliveryLocationId;
  final int? deliveryZone;
  final int? boothNumber;
  final String deliveryMode;
  final String? fixedBoothName;
  final String locationHelpText;
  final String deliveryNotes;
  final List<Map<String, dynamic>> items;

  const OrderSummary({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.total,
    required this.paymentStatus,
    required this.deliveryStatus,
    this.deliveryLocation,
    this.deliveryLocationId,
    this.deliveryZone,
    this.boothNumber,
    this.deliveryMode = 'general',
    this.fixedBoothName,
    this.locationHelpText = '',
    required this.deliveryNotes,
    required this.items,
  });
  factory OrderSummary.fromJson(Map<String, dynamic> json) => OrderSummary(
    id: json['id'] as String,
    customerId: json['customer_id'] as String,
    customerName:
        (json['customers'] as Map<String, dynamic>?)?['display_name']
            as String? ??
        'Cliente',
    total: json['total'] as int? ?? 0,
    paymentStatus: json['payment_status'] as String? ?? 'pending',
    deliveryStatus: json['delivery_status'] as String? ?? 'pending',
    deliveryLocation:
        (json['delivery_locations'] as Map<String, dynamic>?)?['name']
            as String?,
    deliveryLocationId: json['delivery_location_id'] as String?,
    deliveryZone: json['delivery_zone'] as int?,
    boothNumber: json['booth_number'] as int?,
    deliveryMode: json['delivery_mode'] as String? ?? 'general',
    fixedBoothName: json['fixed_booth_name'] as String?,
    locationHelpText:
        json['location_help_text'] as String? ??
        (json['delivery_locations']
                as Map<String, dynamic>?)?['location_help_text']
            as String? ??
        '',
    deliveryNotes: json['delivery_notes'] as String? ?? '',
    items: List<Map<String, dynamic>>.from(
      json['order_items'] as List<dynamic>? ?? const [],
    ),
  );
}
