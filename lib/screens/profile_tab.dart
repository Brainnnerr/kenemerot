import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../login_screen.dart';
import '../theme_manager.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();
  String? _avatarUrl;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    final user = _supabase.auth.currentUser;
    _avatarUrl = user?.userMetadata?['avatar_url'];
  }

  // --- Image Picker from Photos / Gallery ---
  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 500,
        maxHeight: 500,
      );

      if (image == null) return;

      setState(() => _isUploading = true);

      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final bytes = await image.readAsBytes();
      final fileExt = image.path.split('.').last;
      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = '${user.id}/$fileName';

      await _supabase.storage.from('avatars').uploadBinary(
            filePath,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl =
          _supabase.storage.from('avatars').getPublicUrl(filePath);

      await _supabase.auth.updateUser(
        UserAttributes(data: {'avatar_url': publicUrl}),
      );

      if (mounted) {
        setState(() {
          _avatarUrl = publicUrl;
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated successfully!'),
            backgroundColor: Color(0xFF0F5B33),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeProfileAvatar() async {
    try {
      await _supabase.auth.updateUser(
        UserAttributes(data: {'avatar_url': null}),
      );
      if (mounted) {
        setState(() => _avatarUrl = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo removed.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error removing avatar: $e');
    }
  }

  // --- Delete Account Modal Confirmation ---
  void _showDeleteAccountDialog(BuildContext context) {
    bool isLoading = false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.red.shade600, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    'Delete Account',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              content: Text(
                'Are you sure you want to permanently delete your account? This action cannot be undone and all your saved preferences will be erased.',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black87,
                  height: 1.4,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          setDialogState(() => isLoading = true);

                          final navigator = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);

                          try {
                            // Call RPC function or signOut session after deletion request
                            await _supabase.auth.signOut();

                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);

                            navigator.pushAndRemoveUntil(
                              MaterialPageRoute(
                                  builder: (_) => const LoginScreen()),
                              (route) => false,
                            );

                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Account successfully deleted.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } catch (e) {
                            setDialogState(() => isLoading = false);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Failed to delete account: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Delete',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- Change Password Dialog Modal ---
  void _showChangePasswordModal(BuildContext context) {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureNewPassword = true;
    bool obscureConfirmPassword = true;
    bool isLoading = false;
    String? errorMessage;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Change Password',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F5B33),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: isDark ? Colors.white70 : Colors.black87),
                        onPressed: () => Navigator.pop(modalContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade400),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.red.shade300, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: TextStyle(
                                  color: Colors.red.shade200, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextField(
                    controller: newPasswordController,
                    obscureText: obscureNewPassword,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      labelStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey.shade700),
                      prefixIcon: Icon(Icons.lock_outline_rounded,
                          color: isDark ? Colors.white70 : Colors.grey.shade600),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureNewPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: isDark ? Colors.white70 : Colors.grey.shade600,
                        ),
                        onPressed: () {
                          setModalState(() {
                            obscureNewPassword = !obscureNewPassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: confirmPasswordController,
                    obscureText: obscureConfirmPassword,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      labelStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey.shade700),
                      prefixIcon: Icon(Icons.lock_reset_rounded,
                          color: isDark ? Colors.white70 : Colors.grey.shade600),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureConfirmPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: isDark ? Colors.white70 : Colors.grey.shade600,
                        ),
                        onPressed: () {
                          setModalState(() {
                            obscureConfirmPassword = !obscureConfirmPassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F5B33),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: isLoading
                          ? null
                          : () async {
                              final pass = newPasswordController.text.trim();
                              final confirm =
                                  confirmPasswordController.text.trim();

                              if (pass.length < 6) {
                                setModalState(() {
                                  errorMessage =
                                      'Password must be at least 6 characters.';
                                });
                                return;
                              }
                              if (pass != confirm) {
                                setModalState(() {
                                  errorMessage = 'Passwords do not match.';
                                });
                                return;
                              }

                              setModalState(() {
                                isLoading = true;
                                errorMessage = null;
                              });

                              final messenger = ScaffoldMessenger.of(context);
                              final navigator = Navigator.of(modalContext);

                              try {
                                final session = _supabase.auth.currentSession;
                                if (session == null) {
                                  throw 'Session expired. Please log in again.';
                                }

                                await _supabase.auth.updateUser(
                                  UserAttributes(password: pass),
                                );

                                if (!modalContext.mounted) return;

                                navigator.pop();
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Password updated successfully!'),
                                    backgroundColor: Color(0xFF0F5B33),
                                  ),
                                );
                              } on AuthException catch (e) {
                                setModalState(() {
                                  isLoading = false;
                                  errorMessage = e.message;
                                });
                              } catch (e) {
                                setModalState(() {
                                  isLoading = false;
                                  errorMessage =
                                      'Connection error. Please check your network or try logging in again.';
                                });
                              }
                            },
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Update Password',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- Change Email Dialog Modal ---
  void _showChangeEmailModal(BuildContext context) {
    final emailController = TextEditingController();
    bool isLoading = false;
    String? errorMessage;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Change Email Address',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F5B33),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: isDark ? Colors.white70 : Colors.black87),
                        onPressed: () => Navigator.pop(modalContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade400),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.red.shade300, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: TextStyle(
                                  color: Colors.red.shade200, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      labelText: 'New Email Address',
                      labelStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey.shade700),
                      prefixIcon: Icon(Icons.email_outlined,
                          color: isDark ? Colors.white70 : Colors.grey.shade600),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F5B33),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: isLoading
                          ? null
                          : () async {
                              final newEmail = emailController.text.trim();

                              if (newEmail.isEmpty || !newEmail.contains('@')) {
                                setModalState(() {
                                  errorMessage =
                                      'Please enter a valid email address.';
                                });
                                return;
                              }

                              setModalState(() {
                                isLoading = true;
                                errorMessage = null;
                              });

                              final messenger = ScaffoldMessenger.of(context);
                              final navigator = Navigator.of(modalContext);

                              try {
                                await _supabase.auth.updateUser(
                                  UserAttributes(email: newEmail),
                                );

                                if (!modalContext.mounted) return;

                                navigator.pop();
                                setState(() {});
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Confirmation email sent! Please check your new inbox to confirm.'),
                                    backgroundColor: Color(0xFF0F5B33),
                                  ),
                                );
                              } on AuthException catch (e) {
                                setModalState(() {
                                  isLoading = false;
                                  errorMessage = e.message;
                                });
                              } catch (e) {
                                setModalState(() {
                                  isLoading = false;
                                  errorMessage =
                                      'Failed to update email. Please try again.';
                                });
                              }
                            },
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Update Email',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- Show Photo Bottom Sheet Modal ---
  void _showProfilePicOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined,
                    color: Color(0xFF0F5B33)),
                title: const Text('Choose Photo from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage();
                },
              ),
              if (_avatarUrl != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Remove Profile Photo',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _removeProfileAvatar();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleSignOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    await _supabase.auth.signOut();
    if (!mounted) return;

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final fullName =
        (user?.userMetadata?['full_name'] ?? 'ESSU STUDENT').toString().toUpperCase();
    final email = user?.email ?? 'No email provided';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryHeaderColor =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFF0F5B33);
    final textPrimaryColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- TOP AESTHETIC HEADER ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 60, bottom: 32),
              decoration: BoxDecoration(
                color: primaryHeaderColor,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(32),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'Profile',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Avatar Stack with Camera Badge
                  GestureDetector(
                    onTap: () => _showProfilePicOptions(context),
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.white,
                          backgroundImage: _avatarUrl != null
                              ? NetworkImage(_avatarUrl!)
                              : null,
                          child: _avatarUrl == null
                              ? Text(
                                  fullName.isNotEmpty ? fullName[0] : 'U',
                                  style: TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                    color: primaryHeaderColor,
                                  ),
                                )
                              : null,
                        ),
                        if (_isUploading)
                          Positioned.fill(
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black45,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // User Full Name (BOLD, ALL UPPERCASE)
                  Text(
                    fullName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Kenemberlo text
                  const Text(
                    'kenemberlo',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // --- USER INFORMATION CARD ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildDataRow(
                      label: 'Email',
                      value: email,
                      textColor: textPrimaryColor,
                    ),
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                    _buildDataRow(
                      label: 'Campus',
                      value: 'ESSU Main Campus',
                      textColor: textPrimaryColor,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // --- ACTION OPTIONS CARD ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Change Email Option
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F5B33).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.email_outlined,
                          color: Color(0xFF0F5B33),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Change Email',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: textPrimaryColor,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: Colors.grey),
                      onTap: () => _showChangeEmailModal(context),
                    ),

                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),

                    // Change Password Option
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F5B33).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.lock_outline_rounded,
                          color: Color(0xFF0F5B33),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Change Password',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: textPrimaryColor,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: Colors.grey),
                      onTap: () => _showChangePasswordModal(context),
                    ),

                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),

                    // Dark Mode Switch Preference
                    SwitchListTile(
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F5B33).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          ThemeManager.isDarkMode
                              ? Icons.dark_mode_rounded
                              : Icons.dark_mode_outlined,
                          color: const Color(0xFF0F5B33),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Dark Mode',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: textPrimaryColor,
                        ),
                      ),
                      activeThumbColor: const Color(0xFF0F5B33),
                      value: ThemeManager.isDarkMode,
                      onChanged: (val) async {
                        await ThemeManager.toggleTheme(val);
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // --- ACCOUNT DELETION & SIGN OUT BUTTONS ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                children: [
                  // Sign Out Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _handleSignOut(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.red.shade900.withValues(alpha: 0.2)
                            : Colors.red.shade50,
                        foregroundColor:
                            isDark ? Colors.red.shade300 : Colors.red.shade700,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                              color: isDark
                                  ? Colors.red.shade800
                                  : Colors.red.shade200),
                        ),
                      ),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text(
                        'Sign Out Account',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Delete Account Action Text Button
                  TextButton.icon(
                    onPressed: () => _showDeleteAccountDialog(context),
                    icon: Icon(Icons.delete_forever_rounded,
                        color: Colors.red.shade400, size: 20),
                    label: Text(
                      'Delete Account Permanently',
                      style: TextStyle(
                        color: Colors.red.shade400,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow({
    required String label,
    required String value,
    required Color textColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}