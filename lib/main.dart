import 'dart:async';
import 'dart:convert';

import 'location_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// Android Emulator: http://10.0.2.2:5055
// Có thể đổi bằng --dart-define=API_BASE_URL=...
const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:5055',
);

const FlutterSecureStorage secureStorage =
    FlutterSecureStorage();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('WORKTIME GPS ADDRESS UPDATE 2');
  runApp(const WorkTimeApp());
}

// ============================================
// 1. CAU HINH UNG DUNG
// ============================================

class WorkTimeApp extends StatelessWidget {
  const WorkTimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WorkTime',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1769E0),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

// ============================================
// 2. XU LY KET NOI BACKEND API
// ============================================

class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => message;
}

class WorkTimeApi {
  static Future<dynamic> login(
    String email,
    String password,
  ) {
    return _post(
      '/api/auth/login',
      data: {
        'email': email,
        'password': password,
      },
    );
  }

  static Future<dynamic> get(
    String path,
    String token,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl$path'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('Kết nối quá thời gian chờ.');
    } catch (_) {
      throw ApiException(
        'Không thể kết nối đến WorkTime API.',
      );
    }
  }

  static Future<dynamic> post(
    String path,
    String token, {
    Map<String, dynamic>? data,
  }) {
    return _post(
      path,
      token: token,
      data: data ?? {},
    );
  }

  static Future<dynamic> _post(
    String path, {
    String? token,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (token != null)
                'Authorization': 'Bearer $token',
            },
            body: jsonEncode(data ?? {}),
          )
          .timeout(const Duration(seconds: 15));

      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('Kết nối quá thời gian chờ.');
    } catch (_) {
      throw ApiException(
        'Không thể kết nối đến WorkTime API.',
      );
    }
  }

  static dynamic _handleResponse(
    http.Response response,
  ) {
    dynamic data;

    try {
      data = response.body.isEmpty
          ? null
          : jsonDecode(response.body);
    } catch (_) {
      data = null;
    }

    if (response.statusCode >= 200 &&
        response.statusCode < 300) {
      return data;
    }

    String message;

    switch (response.statusCode) {
      case 400:
        message = 'Dữ liệu gửi lên không hợp lệ.';
        break;
      case 401:
        message = 'Sai thông tin đăng nhập hoặc phiên đã hết hạn.';
        break;
      case 403:
        message = 'Bạn không có quyền thực hiện chức năng này.';
        break;
      case 404:
        message = 'Không tìm thấy API.';
        break;
      case 409:
        message = 'Dữ liệu đã tồn tại hoặc bị trùng.';
        break;
      default:
        message = 'Lỗi máy chủ: HTTP ${response.statusCode}.';
    }

    if (data is Map && data['message'] is String) {
      message = data['message'] as String;
    } else if (data is Map && data['errors'] is Map) {
      // ASP.NET Core ModelState trả lỗi theo dạng {"field": ["..."]}.
      final validationMessages = <String>[];
      (data['errors'] as Map).forEach((field, details) {
        if (details is List) {
          validationMessages.addAll(
            details.map((item) => '$field: $item'),
          );
        } else {
          validationMessages.add('$field: $details');
        }
      });
      if (validationMessages.isNotEmpty) {
        message = validationMessages.join('\n');
      }
    } else if (data is Map &&
        data['errors'] is List &&
        (data['errors'] as List).isNotEmpty) {
      message = (data['errors'] as List).join(', ');
    }

    throw ApiException(message);
  }
}

// ============================================
// 3. MAN HINH DANG NHAP
// ============================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _hidePassword = true;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await WorkTimeApi.login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (response is! Map) {
        throw ApiException('Phản hồi đăng nhập không hợp lệ.');
      }

      final token = response['accessToken'];

      if (token is! String || token.isEmpty) {
        throw ApiException('Backend không trả về JWT.');
      }

      final user = response['user'];

      if (user is! Map) {
        throw ApiException('Thiếu thông tin người dùng.');
      }

      final roles = (user['roles'] as List? ?? [])
          .map((value) => value.toString())
          .toList();

      final email = user['email']?.toString() ??
          _emailController.text.trim();

      await secureStorage.write(
        key: 'access_token',
        value: token,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            email: email,
            roles: roles,
            token: token,
          ),
        ),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Đăng nhập không thành công.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 420,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.access_time_filled,
                      size: 78,
                      color: Color(0xFF1769E0),
                    ),
                    const SizedBox(height: 12),

                    const Text(
                      'WorkTime',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Hệ thống quản lý chấm công',
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 40),

                    const Text(
                      'Đăng nhập',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _emailController,
                      keyboardType:
                          TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon:
                            Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';

                        if (email.isEmpty) {
                          return 'Vui lòng nhập email';
                        }

                        if (!email.contains('@')) {
                          return 'Email không hợp lệ';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _hidePassword,
                      onFieldSubmitted: (_) {
                        if (!_isLoading) _login();
                      },
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu',
                        prefixIcon:
                            const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _hidePassword = !_hidePassword;
                            });
                          },
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Vui lòng nhập mật khẩu';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed:
                            _isLoading ? null : _login,
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Đăng nhập'),
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Đăng nhập bằng tài khoản '
                      'được cấp bởi quản trị viên.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================
// 4. TRANG CHU THEO VAI TRO
// ============================================

class DashboardScreen extends StatefulWidget {
  final String email;
  final List<String> roles;
  final String token;

  const DashboardScreen({
    super.key,
    required this.email,
    required this.roles,
    required this.token,
  });

  @override
  State<DashboardScreen> createState() =>
      _DashboardScreenState();
}

class _DashboardScreenState
    extends State<DashboardScreen> {
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _isLoadingAddress = false;

  // Địa chỉ đọc được từ GPS, chỉ để hiển thị cho nhân viên.
  // Backend vẫn nhận vĩ độ và kinh độ để kiểm tra chấm công.
  String? _currentAddress;
  double? _locationAccuracy;

  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _employees = [];

  bool get _isAdmin =>
      widget.roles.contains('Admin');

  bool get _isEmployee =>
      widget.roles.contains('Employee');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      if (_isAdmin) {
        final data = await WorkTimeApi.get(
          '/api/employees',
          widget.token,
        );

        if (data is List) {
          _employees = data
              .whereType<Map>()
              .map((e) =>
                  Map<String, dynamic>.from(e))
              .toList();
        } else {
          _employees = [];
        }
      } else if (_isEmployee) {
        final data = await WorkTimeApi.get(
          '/api/attendance/mine',
          widget.token,
        );

        if (data is Map &&
            data['records'] is List) {
          _records = (data['records'] as List)
              .whereType<Map>()
              .map((e) =>
                  Map<String, dynamic>.from(e))
              .toList();
        } else {
          _records = [];
        }
      }
    } on ApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }



  // Người dùng có thể chủ động xem tên đường trước khi Check-in.
  Future<void> _refreshCurrentAddress() async {
    if (_isLoadingAddress || _isSubmitting) return;

    setState(() {
      _isLoadingAddress = true;
      _currentAddress = null;
      _locationAccuracy = null;
    });

    try {
      final details = await LocationService.getLocationDetails();
      if (!mounted) return;

      setState(() {
        _currentAddress = details.address;
        _locationAccuracy = details.accuracy;
      });
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLoadingAddress = false);
      }
    }
  }

  // Lấy GPS khi bắt đầu cả Check-in và Check-out.
  // Thành công chỉ được thông báo sau khi API trả HTTP 2xx.
  Future<void> _attendanceAction(String endpoint) async {
    if (_isSubmitting || _isLoadingAddress) return;

    final isCheckIn = endpoint.endsWith('/checkin');
    final actionName = isCheckIn ? 'Check-in' : 'Check-out';

    setState(() => _isSubmitting = true);

    try {
      // Mỗi thao tác đều đọc vị trí MỚI, không dùng tọa độ lần trước.
      final position = await LocationService.getCurrentLocation();
      if (!mounted) return;

      debugPrint(
        '$actionName GPS: ${position.latitude}, '
        '${position.longitude}, sai số ${position.accuracy}m',
      );

      // Giữ nguyên hợp đồng Backend hiện tại:
      // Check-in gửi latitude/longitude; Check-out gửi {}.
      // Việc lưu tọa độ Check-out cần mở rộng Backend riêng.
      final requestBody = <String, dynamic>{};
      if (isCheckIn) {
        requestBody['latitude'] = position.latitude;
        requestBody['longitude'] = position.longitude;
      }

      // Nếu API lỗi (400/401/500...), không được báo thành công.
      await WorkTimeApi.post(
        endpoint,
        widget.token,
        data: requestBody,
      );

      if (!mounted) return;

      // Tra cứu tên đường sau khi API đã ghi nhận thành công.
      // Geocoding lỗi không khiến thao tác chấm công thất bại.
      final address =
          await LocationService.getReadableAddress(position);
      if (!mounted) return;

      setState(() {
        _currentAddress = address;
        _locationAccuracy = position.accuracy;
      });

      // Đồng bộ trạng thái nút Check-in/Check-out và lịch sử.
      await _loadData();
      if (!mounted) return;

      // Thông báo rõ ràng cả kết quả và tên đường/vị trí hiện tại.
      await _showAttendanceSuccess(
        actionName: actionName,
        address: address,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } catch (error) {
      if (!mounted) return;

      final message = error.toString().replaceFirst('Exception: ', '');
      _showMessage('$actionName chưa thành công: $message');
      debugPrint('$actionName error: $error');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showAttendanceSuccess({
    required String actionName,
    required String address,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    if (!mounted) return;

    // Chỉ hiển thị tọa độ dự phòng nếu không có địa chỉ từ bản đồ.
    final noRoadName = address.startsWith('Không') ||
        address.startsWith('Chưa');
    final displayAddress = noRoadName
        ? '$address\n'
            'Tọa độ: ${latitude.toStringAsFixed(6)}, '
            '${longitude.toStringAsFixed(6)}'
        : address;

    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final time = '${two(now.hour)}:${two(now.minute)} '
        '${two(now.day)}/${two(now.month)}/${now.year}';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 10),
            Expanded(child: Text('$actionName thành công!')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Thời gian: $time'),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.location_on, color: Colors.blue),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Vị trí hiện tại',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(displayAddress),
              const SizedBox(height: 8),
              Text(
                'Sai số GPS khoảng ${accuracy.toStringAsFixed(0)} m',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _logout() async {
    await secureStorage.delete(
      key: 'access_token',
    );

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  String _formatTime(dynamic value) {
    if (value == null) return 'Chưa check-out';

    final date = DateTime.tryParse(
      value.toString(),
    );

    if (date == null) return value.toString();

    final local = date.toLocal();

    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/'
        '${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final role = _isAdmin
        ? 'Admin'
        : _isEmployee
            ? 'Employee'
            : widget.roles.join(', ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('WorkTime'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.account_circle,
                      size: 54,
                      color: Color(0xFF1769E0),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Xin chào!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(widget.email),
                    const SizedBox(height: 6),
                    Text('Vai trò: $role'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_isAdmin)
              _buildAdminContent()
            else if (_isEmployee)
              _buildEmployeeContent()
            else
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Giao diện cho vai trò này '
                    'đang được phát triển.',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 5. TRANG CHU ADMIN
  // ==========================================

  Widget _buildAdminContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quản lý nhân viên',
          style: Theme.of(context)
              .textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Tổng số nhân viên: ${_employees.length}',
        ),
        const SizedBox(height: 12),

        if (_employees.isEmpty)
          const Card(
            child: ListTile(
              title: Text(
                'Chưa có dữ liệu nhân viên.',
              ),
            ),
          ),

        ..._employees.map((employee) {
          return Card(
            child: ListTile(
              leading:
                  const Icon(Icons.person_outline),
              title: Text(
                employee['fullName']
                        ?.toString() ??
                    'Chưa có tên',
              ),
              subtitle: Text(
                employee['email']
                        ?.toString() ??
                    '',
              ),
              trailing: Text(
                employee['role']
                        ?.toString() ??
                    'Employee',
              ),
            ),
          );
        }),
      ],
    );
  }

  // ==========================================
  // 6. TRANG CHU EMPLOYEE
  // ==========================================

  Widget _buildEmployeeContent() {
    final hasOpenShift = _records.any(
      (record) => record['checkOutTime'] == null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chấm công',
          style: Theme.of(context)
              .textTheme.titleLarge,
        ),
        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                Text(
                  hasOpenShift
                      ? 'Bạn đang trong ca làm việc'
                      : 'Hiện chưa có ca đang mở',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 8),
                const Text(
                  'GPS + Tên đường • bản cập nhật 2',
                  style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                ),
                const SizedBox(height: 12),

                // Hiển thị tên đường/phường/thành phố từ GPS.
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Vị trí hiện tại',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentAddress ??
                            'Chưa xác định tên đường. '
                                'Nhấn nút bên dưới để lấy vị trí.',
                        style: TextStyle(
                          fontSize: 13,
                          color: _currentAddress == null
                              ? Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                              : null,
                        ),
                      ),
                      if (_locationAccuracy != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Sai số GPS khoảng '
                          '${_locationAccuracy!.toStringAsFixed(0)} m',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                OutlinedButton.icon(
                  onPressed: (_isLoadingAddress || _isSubmitting)
                      ? null
                      : _refreshCurrentAddress,
                  icon: _isLoadingAddress
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: Text(
                    _isLoadingAddress
                        ? 'Đang tìm tên đường...'
                        : 'Xem tên đường hiện tại',
                  ),
                ),

                const SizedBox(height: 12),

                FilledButton.icon(
                  onPressed: (_isSubmitting ||
                          _isLoadingAddress ||
                          hasOpenShift)
                      ? null
                      : () => _attendanceAction(
                            '/api/attendance/checkin',
                          ),
                  icon: const Icon(Icons.login),
                  label: const Text(
                    'Check-in bằng GPS',
                  ),
                ),

                const SizedBox(height: 10),

                OutlinedButton.icon(
                  onPressed: (_isSubmitting ||
                          _isLoadingAddress ||
                          !hasOpenShift)
                      ? null
                      : () => _attendanceAction(
                            '/api/attendance/checkout',
                          ),
                  icon: const Icon(Icons.logout),
                  label: const Text('Check-out bằng GPS'),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Địa chỉ chỉ giúp bạn nhận biết vị trí. '
                  'Khi Check-in, hệ thống gửi tọa độ GPS lên máy chủ. '
                  'Khi Check-out, GPS được dùng để hiển thị vị trí '
                  'trong thông báo thành công; Backend hiện chưa lưu '
                  'tọa độ Check-out.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        Text(
          'Lịch sử chấm công',
          style: Theme.of(context)
              .textTheme.titleLarge,
        ),

        const SizedBox(height: 12),

        if (_records.isEmpty)
          const Card(
            child: ListTile(
              title: Text(
                'Chưa có lịch sử chấm công.',
              ),
            ),
          ),

        ..._records.map((record) {
          final checkedOut =
              record['checkOutTime'] != null;

          return Card(
            child: ListTile(
              leading: Icon(
                checkedOut
                    ? Icons.check_circle
                    : Icons.access_time,
                color: checkedOut
                    ? Colors.green
                    : Colors.orange,
              ),
              title: Text(
                'Check-in: '
                '${_formatTime(record['checkInTime'])}',
              ),
              subtitle: Text(
                'Check-out: '
                '${_formatTime(record['checkOutTime'])}',
              ),
              isThreeLine: false,
            ),
          );
        }),
      ],
    );
  }
}
