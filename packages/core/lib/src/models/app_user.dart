class AppUser {
  const AppUser({
    required this.id,
    this.email,
    this.customerId,
    this.role,
  });

  final String id;
  final String? email;
  final String? customerId;
  final String? role;
}
