// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:config_parser/config_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider exposing [SubscriptionFetcher] for fetching and parsing remote
/// subscription URLs.
///
/// Backed by a standard [SubscriptionFetcher] using [HttpClientTransport] in
/// production. Overridden in tests to mock the network transport.
final Provider<SubscriptionFetcher> subscriptionFetcherProvider =
    Provider<SubscriptionFetcher>((ref) {
      return SubscriptionFetcher();
    });
