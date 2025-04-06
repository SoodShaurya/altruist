import 'package:altruist/features/visualiser/view/visualiser_page.dart'; // Import the new page
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isCameraEnabled = true; // State for the camera toggle
  final PanelController _panelController =
      PanelController(); // Controller for the panel

  @override
  Widget build(BuildContext context) {
    // Define colors or use Theme
    const Color backgroundColor = Color(0xFF1E1E1E); // Dark background
    const Color panelColor = Color(0xFF2A2A2A); // Slightly lighter panel
    const Color accentColor = Colors.white;
    const Color inactiveColor = Colors.grey;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Make AppBar transparent
        elevation: 0, // Remove shadow
        leading: IconButton(
          icon: const Icon(Icons.menu, color: accentColor),
          onPressed: () {
            // TODO: Implement drawer or menu action
          },
        ),
        title: const Text(
          'Altruist',
          style: TextStyle(color: accentColor, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline, color: accentColor),
            onPressed: () {
              // TODO: Implement profile action
            },
          ),
        ],
      ),
      body: SlidingUpPanel(
        controller: _panelController,
        minHeight: 100, // Increased height of the collapsed panel
        maxHeight: MediaQuery.of(context).size.height *
            0.5, // Panel expands to half screen
        parallaxEnabled: true,
        parallaxOffset: .5,
        color: panelColor, // Background color of the panel
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24.0),
          topRight: Radius.circular(24.0),
        ),
        // Content visible when the panel is collapsed (the bottom bar)
        collapsed: _buildCollapsedPanel(),
        // Content visible when the panel is expanded
        panel: _buildExpandedPanel(),
        // Content behind the sliding panel
        body: _buildBodyContent(),
      ),
    );
  }

  Widget _buildCollapsedPanel() {
    const Color accentColor = Colors.white;
    const Color inactiveColor = Colors.grey;

    // GestureDetector to handle tap for opening the panel
    return GestureDetector(
      onTap: () {
        if (_panelController.isPanelClosed) {
          _panelController.open();
        }
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF2A2A2A), // Match panel color explicitly if needed
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24.0),
            topRight: Radius.circular(24.0),
          ),
        ),
        // Use Column to align content to the top
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start, // Align children to the top
          children: [
            Padding( // Add padding around the Row
              padding: const EdgeInsets.only(left: 25.0, right: 25.0, top: 20.0), // Adjust top padding as needed
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Logo
                  SvgPicture.asset(
                    'assets/icons/logo.svg',
                    height: 40, // Adjust size as needed
                    colorFilter:
                        const ColorFilter.mode(accentColor, BlendMode.srcIn),
                  ),
                  // Center: Settings text and icon
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center, // Center within its own space
                    children: [
                      const Icon(Icons.keyboard_arrow_up,
                          color: inactiveColor, size: 20),
                      const SizedBox(height: 2),
                      const Text(
                        'settings',
                        style: TextStyle(color: inactiveColor, fontSize: 12),
                      ),
                    ],
                  ),
                  // Right: Camera Toggle Button
                  SizedBox(
                     height: 40, // Match logo height
                     width: 40,  // Ensure circular aspect ratio
                     child: OutlinedButton(
                       onPressed: () {
                         setState(() {
                           _isCameraEnabled = !_isCameraEnabled;
                         });
                       },
                       style: OutlinedButton.styleFrom(
                         shape: const CircleBorder(),
                         padding: EdgeInsets.zero, // Remove default padding
                         side: BorderSide(color: inactiveColor), // Outline color
                         foregroundColor: accentColor, // Icon color for ripple effect
                       ),
                       child: Icon(
                         _isCameraEnabled ? Icons.videocam_outlined : Icons.videocam_off_outlined,
                         color: accentColor,
                         size: 23, // Adjust icon size as needed
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedPanel() {
    // Placeholder content for the expanded panel
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A), // Match panel color explicitly if needed
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24.0),
          topRight: Radius.circular(24.0),
        ),
      ),
      child: const Center(
        child: Text(
          "Expanded Panel Content",
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }

   Widget _buildBodyContent() {
    const Color accentColor = Colors.white;
    // Content behind the panel
    // Use Align to shift content slightly up from center
    return Align(
      alignment: const Alignment(0.0, -0.1), // Adjust Y value (-1.0 top, 0.0 center, 1.0 bottom)
      child: Column(
        mainAxisSize: MainAxisSize.min, // Important when using Align with Column
        children: [
           Container(
              width: 180, // Adjust size as needed
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accentColor, width: 2),
              ),
              child: const Center(
                child: Text(
                  'Placeholder\ncircle',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: accentColor, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'tap to connect', // Text from the sketch
               style: TextStyle(color: Colors.grey, fontSize: 14),
             ),
             const SizedBox(height: 20.0), // Add space below the text
             ElevatedButton(
               onPressed: () {
                 Navigator.push(
                   context,
                   MaterialPageRoute(builder: (context) => const VisualiserPage()),
                 );
               },
               style: ElevatedButton.styleFrom(
                 backgroundColor: const Color(0xFF2A2A2A), // Button background
                 foregroundColor: Colors.white, // Text color
               ),
               child: const Text('Open Visualiser'),
             ),
             const SizedBox(height: 20.0), // Add some space after the button
             // Removed Spacer
          ],
        ),
      );
   }
}
