# Pac-Man-FPGA-Game
A fully functional hardware implementation of Pac-Man running on a DE1-SoC FPGA, built entirely in SystemVerilog and synthesized using Intel Quartus Prime.

**Pac-Man FPGA — DE1-SoC SystemVerilog Implementation**

A fully functional hardware implementation of Pac-Man running on a DE1-SoC FPGA, built entirely in SystemVerilog and synthesized using Intel Quartus Prime.

**Features**
- 640×480 VGA display with real-time pixel-by-pixel rendering — no frame buffer
- Four ghost controllers with independent AI: three waypoint-based path followers and one circular replay buffer ghost that mirrors Pac-Man's movement history with a delay
- Analog joystick input via ADC controller with pixel-accurate wall collision detection using maze ROM
- 66 collectible dots tracked in a 307,200-bit RAM, with real-time score counting on seven-segment displays and win condition triggered at 14,256 dot pixels consumed
- PWM audio with Pac-Man theme on title screen and waka waka sound during gameplay, generated from frequency lookup tables
- Title, gameplay, win, and lose screens managed by a top-level state machine
- Cheat mode (KEY2) to hide ghosts for demonstration

**Asset Pipeline**
All graphics assets were generated using custom Python scripts:
- Maze and screen images converted from PNG to 1-bit binary hex files for ROM loading via $readmemb
- Ghost sprites stored as 24-bit RGB hex files with magenta (FF00FF) transparency keying, loaded via $readmemh
- Ghost waypoints extracted from color-coded paths drawn in Microsoft Paint, automatically parsed into SystemVerilog hardcoded arrays

**Key Engineering Challenges**
- Fit the full design within the Cyclone V's 3,207 logic array blocks — resolved by reducing the red ghost's replay buffer from 4,096 to 256 entries and adjusting sample rate
- Balanced multiple large ROM blocks (maze, dots, sprites, screens) through careful resource budgeting and 1-bit hex representations

---

Want me to trim this down, or is this the level of detail you want for GitHub?
