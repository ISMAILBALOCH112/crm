/// Tenant membership roles and what each may do in the app.
class TenantRoles {
  TenantRoles._();

  static const admin = 'admin';
  static const agent = 'agent';

  static bool isAdmin(String? role) => role == admin;

  static bool canDeleteOrders(String? role) => isAdmin(role);
  static bool canManageOrderTemplates(String? role) => isAdmin(role);
}
