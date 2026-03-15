import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AdminUserRole { owner, admin, staff }

class _AdminUserRow {
  _AdminUserRow({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
  });

  final String id;
  final String name;
  final String email;
  final AdminUserRole role;
  final bool active;

  _AdminUserRow copyWith({
    String? id,
    String? name,
    String? email,
    AdminUserRole? role,
    bool? active,
  }) {
    return _AdminUserRow(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      active: active ?? this.active,
    );
  }
}

final _dummyUsersProvider = StateProvider<List<_AdminUserRow>>((ref) {
  return <_AdminUserRow>[
    _AdminUserRow(
      id: '1',
      name: 'Owner Kullanıcı',
      email: 'owner@example.com',
      role: AdminUserRole.owner,
      active: true,
    ),
    _AdminUserRow(
      id: '2',
      name: 'Admin Kullanıcı',
      email: 'admin@example.com',
      role: AdminUserRole.admin,
      active: true,
    ),
    _AdminUserRow(
      id: '3',
      name: 'Destek Personeli',
      email: 'staff@example.com',
      role: AdminUserRole.staff,
      active: true,
    ),
  ];
});

final _userSearchProvider = StateProvider<String>((ref) => '');
final _userRoleFilterProvider =
    StateProvider<AdminUserRole?>((ref) => null); // null = Tümü

class SettingsUsersPage extends ConsumerWidget {
  const SettingsUsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final users = ref.watch(_dummyUsersProvider);
    final search = ref.watch(_userSearchProvider).trim().toLowerCase();
    final roleFilter = ref.watch(_userRoleFilterProvider);

    final filtered = users.where((u) {
      if (search.isNotEmpty &&
          !u.name.toLowerCase().contains(search) &&
          !u.email.toLowerCase().contains(search)) {
        return false;
      }
      if (roleFilter != null && u.role != roleFilter) {
        return false;
      }
      return true;
    }).toList();

    return AppScaffold(
      title: 'Kullanıcı & Yetki',
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewUserDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Text(
              'Admin kullanıcılarınızı ve rollerini yönetin.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color
                    ?.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            if (AppResponsive.isMobile(context))
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSearchField(
                    hintText: 'Ad / e-posta ara',
                    padded: false,
                    onChanged: (value) => ref
                        .read(_userSearchProvider.notifier)
                        .state = value,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _RoleFilterChips(roleFilter: roleFilter),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: AppSearchField(
                      hintText: 'Ad / e-posta ara',
                      padded: false,
                      onChanged: (value) => ref
                          .read(_userSearchProvider.notifier)
                          .state = value,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  _RoleFilterChips(roleFilter: roleFilter),
                ],
              ),
            const SizedBox(height: AppSpacing.s12),
            Expanded(
              child: filtered.isEmpty
                  ? const AppEmptyState(
                      title: 'Kullanıcı bulunamadı.',
                      subtitle:
                          'Filtreleri temizleyip tekrar deneyebilirsiniz.',
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final user = filtered[index];
                        return AppListTile(
                          leading: CircleAvatar(
                            child: Text(
                              user.name.isNotEmpty
                                  ? user.name.characters.first.toUpperCase()
                                  : '?',
                            ),
                          ),
                          title: user.name,
                          subtitle: user.email,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildRoleChip(context, user),
                              const SizedBox(width: AppSpacing.s8),
                              PopupMenuButton<String>(
                                itemBuilder: (context) => _buildMenuItems(user),
                                onSelected: (value) => _handleMenuAction(
                                  context,
                                  ref,
                                  user,
                                  value,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}

class _RoleFilterChips extends ConsumerWidget {
  const _RoleFilterChips({required this.roleFilter});

  final AdminUserRole? roleFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = <(String, AdminUserRole?)>[
      ('Tümü', null),
      ('Owner', AdminUserRole.owner),
      ('Admin', AdminUserRole.admin),
      ('Staff', AdminUserRole.staff),
    ];

    return Wrap(
      spacing: AppSpacing.s4,
      children: [
        for (final (label, value) in items)
          ChoiceChip(
            label: Text(label),
            selected: roleFilter == value,
            onSelected: (_) {
              ref.read(_userRoleFilterProvider.notifier).state = value;
            },
          ),
      ],
    );
  }
}

String _roleLabel(AdminUserRole role) {
  switch (role) {
    case AdminUserRole.owner:
      return 'Owner';
    case AdminUserRole.admin:
      return 'Admin';
    case AdminUserRole.staff:
      return 'Staff';
  }
}

Widget _buildRoleChip(BuildContext context, _AdminUserRow user) {
  final theme = Theme.of(context);
  Color bg;
  Color fg;
  switch (user.role) {
    case AdminUserRole.owner:
      bg = theme.colorScheme.primary.withValues(alpha: 0.08);
      fg = theme.colorScheme.primary;
      break;
    case AdminUserRole.admin:
      bg = Colors.blueGrey.withValues(alpha: 0.08);
      fg = Colors.blueGrey.shade700;
      break;
    case AdminUserRole.staff:
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
      break;
  }

  if (!user.active) {
    bg = theme.colorScheme.surfaceContainerHighest;
    fg = theme.colorScheme.onSurfaceVariant;
  }

  return Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s8,
      vertical: AppSpacing.s4,
    ),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      _roleLabel(user.role),
      style: theme.textTheme.bodySmall?.copyWith(
        color: fg,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

List<PopupMenuEntry<String>> _buildMenuItems(_AdminUserRow user) {
  final isOwner = user.role == AdminUserRole.owner;
  final items = <PopupMenuEntry<String>>[];

  items.add(
    PopupMenuItem<String>(
      value: 'changeRole',
      child: Text(isOwner ? 'Rolü değiştir (onaylı)' : 'Rolü değiştir'),
    ),
  );
  items.add(
    PopupMenuItem<String>(
      value: 'toggleActive',
      enabled: !isOwner,
      child: Text(user.active ? 'Pasifleştir' : 'Aktifleştir'),
    ),
  );
  items.add(
    PopupMenuItem<String>(
      value: 'delete',
      enabled: !isOwner,
      child: const Text('Sil'),
    ),
  );

  return items;
}

Future<void> _handleMenuAction(
  BuildContext context,
  WidgetRef ref,
  _AdminUserRow user,
  String action,
) async {
  switch (action) {
    case 'changeRole':
      await _changeRoleDialog(context, ref, user);
      break;
    case 'toggleActive':
      _updateUser(ref, user.copyWith(active: !user.active));
      break;
    case 'delete':
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Kullanıcı silinsin mi?'),
              content: Text(
                '${user.name} kullanıcısını silmek üzeresiniz.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Vazgeç'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Sil'),
                ),
              ],
            ),
          ) ??
          false;
      if (confirmed) {
        _removeUser(ref, user.id);
      }
      break;
  }
}

void _updateUser(WidgetRef ref, _AdminUserRow updated) {
  ref.read(_dummyUsersProvider.notifier).state =
      ref.read(_dummyUsersProvider).map((u) {
    if (u.id == updated.id) return updated;
    return u;
  }).toList();
}

void _removeUser(WidgetRef ref, String id) {
  ref.read(_dummyUsersProvider.notifier).state =
      ref.read(_dummyUsersProvider)
          .where((u) => u.id != id)
          .toList();
}

Future<void> _showNewUserDialog(BuildContext context, WidgetRef ref) async {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  AdminUserRole role = AdminUserRole.staff;
  String? error;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Yeni kullanıcı'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Ad Soyad',
                  ),
                ),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
                DropdownButtonFormField<AdminUserRole>(
                  initialValue: role,
                  decoration: const InputDecoration(
                    labelText: 'Rol',
                  ),
                  items: const [
                    DropdownMenuItem<AdminUserRole>(
                      value: AdminUserRole.owner,
                      child: Text('Owner'),
                    ),
                    DropdownMenuItem<AdminUserRole>(
                      value: AdminUserRole.admin,
                      child: Text('Admin'),
                    ),
                    DropdownMenuItem<AdminUserRole>(
                      value: AdminUserRole.staff,
                      child: Text('Staff'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      role = value;
                    });
                  },
                ),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Vazgeç'),
              ),
              TextButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final email = emailController.text.trim();
                  if (name.isEmpty || email.isEmpty) {
                    setState(() {
                      error = 'Ad ve e-posta zorunludur.';
                    });
                    return;
                  }
                  Navigator.of(context).pop(true);
                },
                child: const Text('Ekle'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result == true) {
    final users = ref.read(_dummyUsersProvider);
    final newUser = _AdminUserRow(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: nameController.text.trim(),
      email: emailController.text.trim(),
      role: role,
      active: true,
    );
    ref.read(_dummyUsersProvider.notifier).state = <_AdminUserRow>[...
        users, newUser];
  }
}

Future<void> _changeRoleDialog(
  BuildContext context,
  WidgetRef ref,
  _AdminUserRow user,
) async {
  var selectedRole = user.role;
  final isOwner = user.role == AdminUserRole.owner;

  final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Rolü değiştir'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isOwner)
                      const Text(
                        'Owner rolünü değiştirmek üzeresiniz. Bu işlem uygulamaya erişimi etkileyebilir.',
                      ),
                    const SizedBox(height: AppSpacing.s8),
                    DropdownButtonFormField<AdminUserRole>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Rol',
                      ),
                      items: const [
                        DropdownMenuItem<AdminUserRole>(
                          value: AdminUserRole.owner,
                          child: Text('Owner'),
                        ),
                        DropdownMenuItem<AdminUserRole>(
                          value: AdminUserRole.admin,
                          child: Text('Admin'),
                        ),
                        DropdownMenuItem<AdminUserRole>(
                          value: AdminUserRole.staff,
                          child: Text('Staff'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          selectedRole = value;
                        });
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Vazgeç'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Kaydet'),
                  ),
                ],
              );
            },
          );
        },
      ) ??
      false;

  if (confirmed) {
    _updateUser(ref, user.copyWith(role: selectedRole));
  }
}
