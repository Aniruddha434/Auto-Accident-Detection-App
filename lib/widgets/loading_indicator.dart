import 'package:flutter/material.dart';

/// A loading indicator with a message for AI processing
class LoadingIndicator extends StatelessWidget {
  final String message;
  final double size;
  
  const LoadingIndicator({
    Key? key,
    this.message = 'Processing your request...',
    this.size = 40.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background pulse animation
                _buildPulseAnimation(context),
                
                // Main spinner
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                  strokeWidth: 3,
                ),
                
                // Center icon
                Icon(
                  Icons.medical_services_outlined,
                  size: size * 0.5,
                  color: Theme.of(context).primaryColor.withOpacity(0.7),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.smart_toy_outlined,
                size: 16,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  /// Builds a pulse animation for the loading indicator
  Widget _buildPulseAnimation(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(seconds: 2),
      curve: Curves.easeInOut,
      builder: (_, value, __) => Opacity(
        opacity: 0.3 * (1.0 - value),
        child: Container(
          width: size * (0.8 + (value * 0.5)),
          height: size * (0.8 + (value * 0.5)),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
        ),
      ),
      onEnd: () => _buildPulseAnimation(context),
    );
  }
}
