import 'package:flutter_riverpod/flutter_riverpod.dart';

/// DashboardPage içeriğini yenilemek için basit bir tetikleyici.
///
/// AdminShell AppBar'daki refresh butonu bu tick'i artırır.
final dashboardRefreshTickProvider = StateProvider<int>((ref) => 0);
