import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class ConnectionStatusWidget extends StatelessWidget {
  final bool isConnected;
  final bool isConnecting;
  final String connectionStatus;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  const ConnectionStatusWidget({
    super.key,
    required this.isConnected,
    required this.isConnecting,
    required this.connectionStatus,
    this.onConnect,
    this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatusIcon(),
                const SizedBox(width: 8),
                Text(
                  '연결 상태',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getStatusBackgroundColor(),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _getStatusBorderColor(),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  _buildStatusIndicator(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      connectionStatus,
                      style: TextStyle(
                        color: _getStatusTextColor(),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isConnecting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isConnected || isConnecting ? null : onConnect,
                    icon: Icon(
                      isConnecting ? MdiIcons.loading : MdiIcons.connection,
                      size: 16,
                    ),
                    label: Text(isConnecting ? '연결 중...' : '연결'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isConnected && !isConnecting ? onDisconnect : null,
                    icon: Icon(MdiIcons.linkOff, size: 16),
                    label: const Text('연결 해제'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    if (isConnecting) {
      return Icon(MdiIcons.loading, color: Colors.orange);
    } else if (isConnected) {
      return Icon(MdiIcons.checkCircle, color: Colors.green);
    } else {
      return Icon(MdiIcons.closeCircle, color: Colors.red);
    }
  }

  Widget _buildStatusIndicator() {
    if (isConnecting) {
      return Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Colors.orange,
          shape: BoxShape.circle,
        ),
      );
    } else if (isConnected) {
      return Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
        ),
      );
    } else {
      return Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      );
    }
  }

  Color _getStatusBackgroundColor() {
    if (isConnecting) {
      return Colors.orange.shade50;
    } else if (isConnected) {
      return Colors.green.shade50;
    } else {
      return Colors.red.shade50;
    }
  }

  Color _getStatusBorderColor() {
    if (isConnecting) {
      return Colors.orange.shade300;
    } else if (isConnected) {
      return Colors.green.shade300;
    } else {
      return Colors.red.shade300;
    }
  }

  Color _getStatusTextColor() {
    if (isConnecting) {
      return Colors.orange.shade800;
    } else if (isConnected) {
      return Colors.green.shade800;
    } else {
      return Colors.red.shade800;
    }
  }
}

