// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/servers/domain/models/server_location_group.dart';

SavedServerProfile _makeServer({
  required String id,
  required String name,
  String server = 'example.com',
  int port = 443,
}) {
  return SavedServerProfile(
    ServerProfile(
      id: id,
      name: name,
      config: VlessOutbound(
        server: server,
        serverPort: port,
        uuid: '11111111-2222-3333-4444-555555555555',
        flow: 'xtls-rprx-vision',
        tls: TlsSettings(enabled: true),
      ),
      addedAt: DateTime.utc(2026, 11, 20),
    ),
  );
}

void main() {
  group('ServerLocationParser', () {
    test('1. Parses flag emoji + city', () {
      // Germany Frankfurt
      final deLoc = ServerLocationParser.parse('🇩🇪 Germany · Frankfurt #1');
      expect(deLoc.countryCode, equals('DE'));
      expect(deLoc.countryName, equals('Germany'));
      expect(deLoc.flagEmoji, equals('🇩🇪'));
      expect(deLoc.cityOrState, equals('Frankfurt'));

      // US New York
      final usLoc = ServerLocationParser.parse('🇺🇸 US - New York 02');
      expect(usLoc.countryCode, equals('US'));
      expect(usLoc.countryName, equals('United States'));
      expect(usLoc.flagEmoji, equals('🇺🇸'));
      expect(usLoc.cityOrState, equals('New York'));

      // Netherlands Amsterdam
      final nlLoc = ServerLocationParser.parse('🇳🇱 Amsterdam | NL-04');
      expect(nlLoc.countryCode, equals('NL'));
      expect(nlLoc.countryName, equals('Netherlands'));
      expect(nlLoc.flagEmoji, equals('🇳🇱'));
      expect(nlLoc.cityOrState, equals('Amsterdam'));
    });

    test('2. Parses country-only remark with cityOrState == null '
        '— no fake city invented', () {
      final deOnly = ServerLocationParser.parse('🇩🇪 Germany #1');
      expect(deOnly.countryCode, equals('DE'));
      expect(deOnly.countryName, equals('Germany'));
      expect(deOnly.flagEmoji, equals('🇩🇪'));
      expect(deOnly.cityOrState, isNull);

      final usOnly = ServerLocationParser.parse('🇺🇸 United States');
      expect(usOnly.countryCode, equals('US'));
      expect(usOnly.countryName, equals('United States'));
      expect(usOnly.flagEmoji, equals('🇺🇸'));
      expect(usOnly.cityOrState, isNull);

      final nlOnly = ServerLocationParser.parse('🇳🇱 NL-01 [vless]');
      expect(nlOnly.countryCode, equals('NL'));
      expect(nlOnly.countryName, equals('Netherlands'));
      expect(nlOnly.flagEmoji, equals('🇳🇱'));
      expect(nlOnly.cityOrState, isNull);
    });

    test('3. Parses ISO-2 & full-name remarks without flag', () {
      // DE_Berlin_01
      final deBerlin = ServerLocationParser.parse('DE_Berlin_01');
      expect(deBerlin.countryCode, equals('DE'));
      expect(deBerlin.countryName, equals('Germany'));
      expect(deBerlin.flagEmoji, equals('🇩🇪'));
      expect(deBerlin.cityOrState, equals('Berlin'));

      // United Kingdom - London
      final ukLondon = ServerLocationParser.parse('United Kingdom - London');
      expect(ukLondon.countryCode, equals('GB'));
      expect(ukLondon.countryName, equals('United Kingdom'));
      expect(ukLondon.flagEmoji, equals('🇬🇧'));
      expect(ukLondon.cityOrState, equals('London'));

      // UK | Manchester
      final ukMcr = ServerLocationParser.parse('UK | Manchester');
      expect(ukMcr.countryCode, equals('GB'));
      expect(ukMcr.countryName, equals('United Kingdom'));
      expect(ukMcr.flagEmoji, equals('🇬🇧'));
      expect(ukMcr.cityOrState, equals('Manchester'));
    });

    test(
      '4. Falls back cleanly to ZZ / Other Locations / 🌐 for generic remarks '
      'and ignores protocol tokens',
      () {
        final generic = ServerLocationParser.parse('My Fast Node 1');
        expect(generic.countryCode, equals('ZZ'));
        expect(generic.countryName, equals('Other Locations'));
        expect(generic.flagEmoji, equals('🌐'));
        expect(generic.cityOrState, isNull);

        final protoOnly = ServerLocationParser.parse(
          'VLESS - REALITY - WS - Fast #1',
        );
        expect(protoOnly.countryCode, equals('ZZ'));
        expect(protoOnly.countryName, equals('Other Locations'));
        expect(protoOnly.flagEmoji, equals('🌐'));
        expect(protoOnly.cityOrState, isNull);

        final empty = ServerLocationParser.parse('   ');
        expect(empty.countryCode, equals('ZZ'));
        expect(empty.countryName, equals('Other Locations'));
        expect(empty.flagEmoji, equals('🌐'));
        expect(empty.cityOrState, isNull);
      },
    );
  });

  group('ServerLocationGrouper', () {
    test('5. Groups hierarchically Country -> City/State -> Servers '
        'with alphabetical ordering (ZZ last, null city last) '
        'and exact totalServerCount', () {
      final s1 = _makeServer(id: 's1', name: '🇺🇸 US - New York 01');
      final s2 = _makeServer(id: 's2', name: '🇺🇸 US - Chicago 01');
      final s3 = _makeServer(id: 's3', name: '🇺🇸 US - Atlanta 01');
      final s4 = _makeServer(id: 's4', name: '🇩🇪 Germany · Frankfurt #1');
      final s5 = _makeServer(id: 's5', name: 'DE_Berlin_01');
      final s6 = _makeServer(id: 's6', name: '🇩🇪 Germany #1');
      final s7 = _makeServer(id: 's7', name: 'My Fast Node 1');

      final groups = ServerLocationGrouper.group([s7, s1, s5, s3, s6, s2, s4]);

      // Expect 3 country groups: DE, US, ZZ
      expect(groups.length, equals(3));

      // 1st country: Germany
      final deGroup = groups[0];
      expect(deGroup.countryCode, equals('DE'));
      expect(deGroup.countryName, equals('Germany'));
      expect(deGroup.flagEmoji, equals('🇩🇪'));
      expect(deGroup.totalServerCount, equals(3));
      expect(deGroup.cities.length, equals(3));
      // Cities ordered: Berlin, Frankfurt, null
      expect(deGroup.cities[0].cityOrState, equals('Berlin'));
      expect(deGroup.cities[0].servers.map((s) => s.id), equals(['s5']));
      expect(deGroup.cities[1].cityOrState, equals('Frankfurt'));
      expect(deGroup.cities[1].servers.map((s) => s.id), equals(['s4']));
      expect(deGroup.cities[2].cityOrState, isNull);
      expect(deGroup.cities[2].servers.map((s) => s.id), equals(['s6']));

      // 2nd country: United States
      final usGroup = groups[1];
      expect(usGroup.countryCode, equals('US'));
      expect(usGroup.countryName, equals('United States'));
      expect(usGroup.flagEmoji, equals('🇺🇸'));
      expect(usGroup.totalServerCount, equals(3));
      expect(usGroup.cities.length, equals(3));
      // Cities ordered: Atlanta, Chicago, New York
      expect(usGroup.cities[0].cityOrState, equals('Atlanta'));
      expect(usGroup.cities[0].servers.map((s) => s.id), equals(['s3']));
      expect(usGroup.cities[1].cityOrState, equals('Chicago'));
      expect(usGroup.cities[1].servers.map((s) => s.id), equals(['s2']));
      expect(usGroup.cities[2].cityOrState, equals('New York'));
      expect(usGroup.cities[2].servers.map((s) => s.id), equals(['s1']));

      // 3rd country: ZZ (Other Locations) sorted LAST
      final zzGroup = groups[2];
      expect(zzGroup.countryCode, equals('ZZ'));
      expect(zzGroup.countryName, equals('Other Locations'));
      expect(zzGroup.flagEmoji, equals('🌐'));
      expect(zzGroup.totalServerCount, equals(1));
      expect(zzGroup.cities.length, equals(1));
      expect(zzGroup.cities[0].cityOrState, isNull);
      expect(zzGroup.cities[0].servers.map((s) => s.id), equals(['s7']));
    });

    test('6. Filters accurately by searchQuery across country, city, '
        'protocol, and server name', () {
      final s1 = _makeServer(
        id: 's1',
        name: '🇺🇸 US - New York 01',
        server: 'nyc.vpn.net',
      );
      final s2 = _makeServer(
        id: 's2',
        name: '🇩🇪 Germany · Frankfurt #1',
        server: 'fra.vpn.net',
      );
      final s3 = _makeServer(
        id: 's3',
        name: 'My Fast Node 1',
        server: 'special-node.org',
      );

      final all = [s1, s2, s3];

      // Search by country name: 'germany'
      final byCountry = ServerLocationGrouper.group(
        all,
        searchQuery: 'germany',
      );
      expect(byCountry.length, equals(1));
      expect(byCountry[0].countryCode, equals('DE'));

      // Search by country code: 'us'
      final byCode = ServerLocationGrouper.group(all, searchQuery: 'us');
      expect(byCode.length, equals(1));
      expect(byCode[0].countryCode, equals('US'));

      // Search by city: 'frankfurt'
      final byCity = ServerLocationGrouper.group(all, searchQuery: 'frankfurt');
      expect(byCity.length, equals(1));
      expect(byCity[0].cities[0].cityOrState, equals('Frankfurt'));

      // Search by protocol: 'vless'
      final byProto = ServerLocationGrouper.group(all, searchQuery: 'vless');
      expect(byProto.length, equals(3));

      // Search by server name: 'Fast'
      final byName = ServerLocationGrouper.group(all, searchQuery: 'Fast');
      expect(byName.length, equals(1));
      expect(byName[0].countryCode, equals('ZZ'));

      // Search with no match: 'xyz999' -> empty list
      final noMatch = ServerLocationGrouper.group(all, searchQuery: 'xyz999');
      expect(noMatch, isEmpty);
    });

    test('7. Regression tests for C1-C6 bugs', () {
      // C1: Comma delimiter
      final c1Loc = ServerLocationParser.parse('🇺🇸 New York, US');
      expect(c1Loc.countryCode, equals('US'));
      expect(c1Loc.cityOrState, equals('New York'));

      // C2: Hyphenated ISO prefix & Trailing digits attached to words
      final c2De = ServerLocationParser.parse('🇩🇪 DE-Frankfurt');
      expect(c2De.countryCode, equals('DE'));
      expect(c2De.cityOrState, equals('Frankfurt'));

      final c2Frankfurt01 = ServerLocationParser.parse(
        '🇩🇪 Germany · Frankfurt01',
      );
      expect(c2Frankfurt01.countryCode, equals('DE'));
      expect(c2Frankfurt01.cityOrState, equals('Frankfurt'));

      // C3: Protocol & VPN noise tokens never misclassified as cities
      final c3Xhttp = ServerLocationParser.parse('🇩🇪 DE | XHTTP | #1');
      expect(c3Xhttp.countryCode, equals('DE'));
      expect(c3Xhttp.cityOrState, isNull);

      final c3Vip = ServerLocationParser.parse('🇺🇸 US - VIP #2');
      expect(c3Vip.countryCode, equals('US'));
      expect(c3Vip.cityOrState, isNull);

      final c3Awg = ServerLocationParser.parse('🇳🇱 NL - AWG - Cloudflare');
      expect(c3Awg.countryCode, equals('NL'));
      expect(c3Awg.cityOrState, isNull);

      // C4: Bracketed and parenthesized ISO-2 codes
      final c4Bracket = ServerLocationParser.parse('[DE] Frankfurt');
      expect(c4Bracket.countryCode, equals('DE'));
      expect(c4Bracket.cityOrState, equals('Frankfurt'));

      final c4Paren = ServerLocationParser.parse('(US) Dallas');
      expect(c4Paren.countryCode, equals('US'));
      expect(c4Paren.cityOrState, equals('Dallas'));

      // C5: Case-insensitive city deduplication
      final sDe1 = _makeServer(id: 'de-1', name: '🇩🇪 Germany · Frankfurt #1');
      final sDe2 = _makeServer(id: 'de-2', name: '🇩🇪 Germany · frankfurt #2');
      final sDe3 = _makeServer(id: 'de-3', name: '🇩🇪 Germany · FRANKFURT #3');
      final c5Groups = ServerLocationGrouper.group([sDe1, sDe2, sDe3]);
      expect(c5Groups.length, equals(1));
      expect(c5Groups[0].cities.length, equals(1));
      expect(c5Groups[0].cities[0].cityOrState, equals('Frankfurt'));
      expect(c5Groups[0].cities[0].servers.length, equals(3));

      // C6: Searching 'z' does NOT return ZZ; valid flag beyond top-53
      final sZz = _makeServer(id: 'zz-1', name: 'Generic Server 1');
      final c6Search = ServerLocationGrouper.group([sZz], searchQuery: 'z');
      expect(c6Search, isEmpty);

      final c6Cyprus = ServerLocationParser.parse('🇨🇾 Cyprus · Limassol');
      expect(c6Cyprus.countryCode, equals('CY'));
      expect(c6Cyprus.countryName, equals('Cyprus'));
      expect(c6Cyprus.flagEmoji, equals('🇨🇾'));
      expect(c6Cyprus.cityOrState, equals('Limassol'));
    });

    test('8. Regression tests for B1-B3 bugs', () {
      // B1: Lowercase words never trigger country codes
      for (final remark in [
        'Fast Server in Cloud',
        'Node at Home',
        'Try it Free',
        'Join us Now',
      ]) {
        final loc = ServerLocationParser.parse(remark);
        expect(
          loc.countryCode,
          equals('ZZ'),
          reason: '$remark must fall back to ZZ',
        );
        expect(loc.countryName, equals('Other Locations'));
      }
      final inMumbai = ServerLocationParser.parse('[IN] Mumbai');
      expect(inMumbai.countryCode, equals('IN'));
      expect(inMumbai.countryName, equals('India'));
      expect(inMumbai.cityOrState, equals('Mumbai'));

      // B2: Strict alphabetic city validation
      final de45ms = ServerLocationParser.parse(
        '🇩🇪 Germany · 45ms · Frankfurt',
      );
      expect(de45ms.countryCode, equals('DE'));
      expect(de45ms.cityOrState, equals('Frankfurt'));

      final deTg = ServerLocationParser.parse('🇩🇪 DE | @MyTelegramChannel');
      expect(deTg.countryCode, equals('DE'));
      expect(deTg.cityOrState, isNull);

      final usTme = ServerLocationParser.parse('🇺🇸 US · t.me · New York');
      expect(usTme.countryCode, equals('US'));
      expect(usTme.cityOrState, equals('New York'));

      // B3: Common countries & CityLocationGroup.hashCode contract
      final noOslo = ServerLocationParser.parse('🇳🇴 Norway · Oslo');
      expect(noOslo.countryCode, equals('NO'));
      expect(noOslo.countryName, equals('Norway'));
      expect(noOslo.flagEmoji, equals('🇳🇴'));
      expect(noOslo.cityOrState, equals('Oslo'));

      final roBuc = ServerLocationParser.parse('🇷🇴 Romania · Bucharest');
      expect(roBuc.countryCode, equals('RO'));
      expect(roBuc.countryName, equals('Romania'));
      expect(roBuc.flagEmoji, equals('🇷🇴'));
      expect(roBuc.cityOrState, equals('Bucharest'));

      final sA = _makeServer(id: 'srv-eq-1', name: 'Server A');
      final sB = _makeServer(id: 'srv-eq-1', name: 'Server A (Copy)');
      final g1 = CityLocationGroup(cityOrState: 'City', servers: [sA]);
      final g2 = CityLocationGroup(cityOrState: 'City', servers: [sB]);
      expect(g1 == g2, isTrue);
      expect(g1.hashCode == g2.hashCode, isTrue);
    });
  });
}
