// Your Firebase configuration
const firebaseConfig = {
  apiKey: "AIzaSyC_cwJ2lBqsDMzWmGIlcBqyBb2BqP3I6aA",
  authDomain: "face-authentication-app-44ddb.firebaseapp.com",
  projectId: "face-authentication-app-44ddb",
  storageBucket: "face-authentication-app-44ddb.firebasestorage.app",
  messagingSenderId: "541867932129",
  appId: "1:541867932129:android:ed73e3859b053c1555faa0"
};

// Initialize Firebase
firebase.initializeApp(firebaseConfig);
const auth = firebase.auth();
const db = firebase.firestore();