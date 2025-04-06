import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:accident_report_system/providers/auth_provider.dart';
import 'package:accident_report_system/models/accident_model.dart';
import 'package:intl/intl.dart';

class AccidentHistoryScreen extends StatefulWidget {
  const AccidentHistoryScreen({super.key});

  @override
  State<AccidentHistoryScreen> createState() => _AccidentHistoryScreenState();
}

class _AccidentHistoryScreenState extends State<AccidentHistoryScreen> {
  bool _isLoading = false;
  List<AccidentModel> _accidents = [];

  @override
  void initState() {
    super.initState();
    _loadAccidentHistory();
  }

  Future<void> _loadAccidentHistory() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      if (authProvider.userModel != null) {
        final userId = authProvider.userModel!.uid;
        
        final QuerySnapshot snapshot = await FirebaseFirestore.instance
            .collection('accidents')
            .where('userId', isEqualTo: userId)
            .orderBy('timestamp', descending: true)
            .get();
        
        final fetchedAccidents = snapshot.docs
            .map((doc) {
              try {
                return AccidentModel.fromMap(doc.data() as Map<String, dynamic>);
              } catch (e) {
                debugPrint('Error parsing accident doc: $e');
                return null;
              }
            })
            .where((accident) => accident != null)
            .cast<AccidentModel>()
            .toList();
            
        setState(() {
          _accidents = fetchedAccidents;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading accident history: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accident History'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _accidents.isEmpty
              ? _buildEmptyState()
              : _buildAccidentList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No accident history',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your accident history will appear here',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccidentList() {
    return ListView.builder(
      itemCount: _accidents.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final accident = _accidents[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(
                Icons.warning_amber,
                color: Colors.white,
              ),
            ),
            title: Text(
              'Accident on ${DateFormat('MMM d, yyyy').format(accident.timestamp)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text('Time: ${DateFormat('h:mm a').format(accident.timestamp)}'),
                Text('Latitude: ${accident.latitude.toStringAsFixed(4)}'),
                Text('Longitude: ${accident.longitude.toStringAsFixed(4)}'),
                Text('Impact Force: ${accident.impactForce.toStringAsFixed(1)}'),
              ],
            ),
            trailing: Icon(
              Icons.arrow_forward_ios,
              color: Theme.of(context).colorScheme.primary,
              size: 16,
            ),
            onTap: () {
              // Navigate to accident details
              // TODO: Implement accident details screen
            },
          ),
        );
      },
    );
  }
} 