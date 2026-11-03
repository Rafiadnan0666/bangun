/// Icon vocabulary for Awake.
///
/// The app deliberately uses Material icons instead of emojis: emojis render
/// with different artwork on every OEM, ignore the pastel palette, and look
/// noisy next to the custom type. Keeping the mapping here also means a new
/// scan target or tone only needs one icon decision.
library;

import 'package:flutter/material.dart';

import '../data/models.dart';

IconData challengeIcon(ChallengeKind kind) => switch (kind) {
  ChallengeKind.math => Icons.calculate_rounded,
  ChallengeKind.scan => Icons.camera_alt_rounded,
  ChallengeKind.mix => Icons.shuffle_rounded,
};

IconData toneIcon(BuiltInTone tone) => switch (tone) {
  BuiltInTone.morningBricks => Icons.wb_sunny_rounded,
  BuiltInTone.twinChime => Icons.notifications_active_rounded,
  BuiltInTone.sirenRush => Icons.crisis_alert_rounded,
  BuiltInTone.digitalChirp => Icons.graphic_eq_rounded,
};

IconData targetGroupIcon(String name) => switch (name) {
  'Common' => Icons.star_rounded,
  'All' => Icons.public_rounded,
  'Food' => Icons.restaurant_rounded,
  'Home' => Icons.chair_rounded,
  'Tech' => Icons.devices_rounded,
  'Outdoors' => Icons.park_rounded,
  'Animals' => Icons.pets_rounded,
  'People' => Icons.person_rounded,
  _ => Icons.category_rounded,
};

/// A compact icon per COCO label. Related objects share a category icon where
/// Material has no literal equivalent; the label text still names the exact
/// target so there is no ambiguity while scanning.
IconData targetIcon(String label) => switch (_alias(label)) {
  'person' => Icons.person_rounded,
  'bicycle' => Icons.directions_bike_rounded,
  'car' => Icons.directions_car_rounded,
  'motorcycle' => Icons.two_wheeler_rounded,
  'airplane' => Icons.flight_rounded,
  'bus' => Icons.directions_bus_rounded,
  'train' => Icons.train_rounded,
  'truck' => Icons.local_shipping_rounded,
  'boat' => Icons.directions_boat_rounded,
  'traffic light' => Icons.traffic_rounded,
  'fire hydrant' => Icons.fire_hydrant_alt_rounded,
  'stop sign' => Icons.report_rounded,
  'parking meter' => Icons.local_parking_rounded,
  'bench' => Icons.event_seat_rounded,
  'bird' ||
  'cat' ||
  'dog' ||
  'horse' ||
  'sheep' ||
  'cow' ||
  'elephant' ||
  'bear' ||
  'zebra' ||
  'giraffe' => Icons.pets_rounded,
  'backpack' => Icons.backpack_rounded,
  'handbag' => Icons.shopping_bag_rounded,
  'tie' => Icons.checkroom_rounded,
  'suitcase' => Icons.luggage_rounded,
  'umbrella' => Icons.umbrella_rounded,
  'frisbee' => Icons.radio_button_unchecked_rounded,
  'skis' || 'snowboard' => Icons.downhill_skiing_rounded,
  'sports ball' => Icons.sports_soccer_rounded,
  'kite' => Icons.air_rounded,
  'baseball bat' || 'baseball glove' => Icons.sports_baseball_rounded,
  'skateboard' => Icons.skateboarding_rounded,
  'surfboard' => Icons.surfing_rounded,
  'tennis racket' => Icons.sports_tennis_rounded,
  'bottle' => Icons.local_drink_rounded,
  'wine glass' => Icons.wine_bar_rounded,
  'cup' => Icons.coffee_rounded,
  'fork' || 'knife' || 'spoon' || 'bowl' => Icons.restaurant_rounded,
  'banana' || 'apple' || 'orange' => Icons.local_dining_rounded,
  'sandwich' || 'hot dog' => Icons.fastfood_rounded,
  'broccoli' || 'carrot' => Icons.eco_rounded,
  'pizza' => Icons.local_pizza_rounded,
  'donut' => Icons.donut_large_rounded,
  'cake' => Icons.cake_rounded,
  'chair' => Icons.chair_rounded,
  'couch' => Icons.weekend_rounded,
  'potted plant' => Icons.yard_rounded,
  'bed' => Icons.bed_rounded,
  'dining table' => Icons.table_restaurant_rounded,
  'toilet' => Icons.wc_rounded,
  'tv' => Icons.tv_rounded,
  'laptop' => Icons.laptop_rounded,
  'mouse' => Icons.mouse_rounded,
  'remote' => Icons.settings_remote_rounded,
  'keyboard' => Icons.keyboard_rounded,
  'cell phone' => Icons.smartphone_rounded,
  'microwave' => Icons.microwave_rounded,
  'oven' => Icons.whatshot_rounded,
  'toaster' => Icons.breakfast_dining_rounded,
  'sink' => Icons.water_drop_rounded,
  'refrigerator' => Icons.kitchen_rounded,
  'book' => Icons.menu_book_rounded,
  'clock' => Icons.schedule_rounded,
  'vase' => Icons.local_florist_rounded,
  'scissors' => Icons.content_cut_rounded,
  'teddy bear' => Icons.toys_rounded,
  'hair drier' => Icons.air_rounded,
  'toothbrush' => Icons.cleaning_services_rounded,
  _ => Icons.center_focus_strong_rounded,
};

String _alias(String label) => switch (label) {
  'glass' => 'wine glass',
  'screen' => 'tv',
  _ => label,
};
