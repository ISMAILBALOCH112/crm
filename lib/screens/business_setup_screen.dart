import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/auth_service.dart';
import '../services/tenant_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

/// Shown right after signup/login when the user isn't part of a business
/// yet. Lets them create a new one or join an existing one via invite code.
/// On success this just updates Firestore — AuthGate's stream listener
/// swaps to HomeScreen automatically, no manual navigation needed here.
class BusinessSetupScreen extends StatefulWidget {
  const BusinessSetupScreen({super.key});

  @override
  State<BusinessSetupScreen> createState() => _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends State<BusinessSetupScreen> {
  final _tenantService = TenantService();
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _inputController = TextEditingController();

  bool _isCreateMode = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isCreateMode) {
        await _tenantService.createTenant(_inputController.text.trim());
      } else {
        await _tenantService.requestToJoin(_inputController.text.trim());
      }
    } catch (e) {
      setState(() => _errorMessage = _isCreateMode
          ? 'Could not create the business. Please try again.'
          : 'That invite code is not valid or has expired.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setMode(bool createMode) {
    setState(() {
      _isCreateMode = createMode;
      _errorMessage = null;
      _inputController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      icon: Icons.storefront_rounded,
      title: 'Set Up Your Business',
      subtitle: 'Create a new business or join an existing one',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModeToggle(isCreateMode: _isCreateMode, onChanged: _setMode)
              .animate()
              .fadeIn(delay: 200.ms, duration: 350.ms),
          const SizedBox(height: 24),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _inputController,
                  textCapitalization: _isCreateMode ? TextCapitalization.words : TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: _isCreateMode ? 'Business Name' : 'Invite Code',
                    prefixIcon: Icon(_isCreateMode ? Icons.business_rounded : Icons.key_rounded),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return _isCreateMode ? 'Business name is required' : 'Invite code is required';
                    }
                    return null;
                  },
                ).animate().fadeIn(delay: 260.ms, duration: 350.ms),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ],
                const SizedBox(height: 24),
                PrimaryButton(
                  label: _isCreateMode ? 'Create Business' : 'Request to Join',
                  isLoading: _isLoading,
                  onPressed: _submit,
                ).animate().fadeIn(delay: 340.ms, duration: 350.ms),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: _isLoading ? null : _authService.logout,
              child: const Text('Log Out'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool isCreateMode;
  final ValueChanged<bool> onChanged;

  const _ModeToggle({required this.isCreateMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Expanded(child: _ModeButton(label: 'Create', isSelected: isCreateMode, onTap: () => onChanged(true))),
          Expanded(child: _ModeButton(label: 'Join', isSelected: !isCreateMode, onTap: () => onChanged(false))),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeButton({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceSolid : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.15), blurRadius: 8)]
              : [],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
