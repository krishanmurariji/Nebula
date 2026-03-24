🌌 Nebula Music Player
<p align="center"> <b>A Premium Neumorphic Music Experience built with Flutter</b> </p> <p align="center"> 🎵 Gramophone UI • ⚡ Smooth Performance • 🫧 Soft UI • 🌍 YouTube Streaming </p>
📸 Screenshots
<!-- Replace these paths with your actual images --> <p align="center"> ![WhatsApp Image 2026-03-24 at 8 02 57 AM](https://github.com/user-attachments/assets/fd27c474-a452-4558-a41a-523f43a63e10)
<img src="screenshots/home.png" width="250"/> <img src="screenshots/player.png" width="250"/> <img src="screenshots/now_playing.png" width="250"/> </p>
✨ Features
🎙️ Interactive Gramophone UI
Realistic vinyl rotation with dynamic needle interaction based on playback
🫧 Neumorphic Design System
Clean soft UI with light & dark mode support
🎯 Haptic Feedback
Feel every interaction — skip, play, like
🔄 Sync-Glow Animation
Record label glows with playback state
🌍 YouTube Audio Streaming
High-quality streaming via youtube_explode_dart
🛠️ Scalable Architecture
Powered by Riverpod 2.0
🛠️ Tech Stack
Category	Technology
Framework	Flutter 3.x
State Management	Riverpod
Audio Engine	just_audio, audio_service
API & Networking	http, youtube_explode_dart
UI/UX	Neumorphism, Custom Animations
Local Storage	shared_preferences
🚀 Getting Started
📌 Prerequisites
Flutter SDK (latest stable)
YouTube Data API v3 Key
⚙️ Installation
# Clone the repository
git clone https://github.com/krishanmurariji/nebula_music_player.git

# Go to project directory
cd nebula_music_player

# Install dependencies
flutter pub get
🔑 Setup API Key
Open Google Cloud Console
Enable YouTube Data API v3
Create API Key

Then add it in your project:

const YOUTUBE_API_KEY = "YOUR_API_KEY_HERE";
▶️ Run App
flutter run
📂 Project Structure
lib/
│── core/          # Constants, themes, utils
│── features/      # Main modules (player, home, search)
│── services/      # API & audio handling
│── providers/     # Riverpod state management
│── widgets/       # Reusable UI components
🚧 Roadmap
 🎵 Offline Playback
 ❤️ Playlist & Favorites
 🔍 Smart Recommendations
 🎚️ Equalizer Support
🤝 Contributing

Contributions are welcome!

# Fork the repo
# Create your branch
git checkout -b feature/YourFeature

# Commit changes
git commit -m "Add YourFeature"

# Push
git push origin feature/YourFeature

Then open a Pull Request 🚀

📄 License

MIT License

👨‍💻 Author

Krishan Murari
Flutter Developer • UI/UX Enthusiast • Marvel Fan 🚀

⭐ Support

If you like this project:

👉 Give it a star on GitHub
👉 Share it with others
