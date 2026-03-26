package com.example.pos;

import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.util.Patterns;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseUser;
import com.google.firebase.firestore.FieldValue;
import com.google.firebase.firestore.FirebaseFirestore;
import com.google.firebase.firestore.SetOptions;

import org.json.JSONObject;

import java.io.IOException;
import java.util.HashMap;
import java.util.Arrays;
import java.util.Locale;
import java.util.Map;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

public class Signup extends AppCompatActivity {

    private EditText fullname, username, password, confirm;
    private TextView  back_btn;
    private TextView status;
    private Button sign_btn;

    private FirebaseAuth auth;
    private FirebaseFirestore db;

    private final OkHttpClient httpClient = new OkHttpClient();

    // ─────────────────────────────────────────────────────────────────────
    // ✅ Replace 192.168.x.x with your computer's actual local IP.
    //    Find it with:  Windows → ipconfig   |   Mac/Linux → hostname -I
    //    Your phone and computer must be on the same Wi-Fi network.
    //    127.0.0.1 only works on an emulator, NOT on a physical device.
    // ─────────────────────────────────────────────────────────────────────
    private static final String BASE_URL = "http://127.0.0.1:8081";

    private String currentStatus = "Empty";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.signup);

        auth = FirebaseAuth.getInstance();
        db   = FirebaseFirestore.getInstance();

        fullname = findViewById(R.id.fullname);
        username = findViewById(R.id.email);
        password = findViewById(R.id.password);
        confirm  = findViewById(R.id.conpassword);
        sign_btn = findViewById(R.id.signbutton);
        status   = findViewById(R.id.status);
        back_btn = findViewById(R.id.login);


        back_btn.setOnClickListener(v ->
                startActivity(new Intent(Signup.this, Login.class))
        );

        password.addTextChangedListener(new TextWatcher() {
            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {
                checkPasswordStrength(s.toString());
            }
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void afterTextChanged(Editable s) {}
        });

        sign_btn.setOnClickListener(v -> registerUser());
    }

    // ══════════════════════════════════════════════════════════════════════
    // REGISTER — with email-uniqueness check BEFORE Firebase Auth
    // ══════════════════════════════════════════════════════════════════════

    private void registerUser() {
        String name      = fullname.getText().toString().trim();
        String userInput = username.getText().toString().trim();
        String pass      = password.getText().toString();
        String conf      = confirm.getText().toString();

        // ── Input validation ──────────────────────────────────────────────
        if (name.isEmpty())           { fullname.setError("Full Name required"); return; }
        if (userInput.isEmpty())      { username.setError("Email required"); return; }
        if (!isEmail(userInput))      { username.setError("Enter valid email"); return; }
        if (pass.isEmpty())           { password.setError("Password required"); return; }
        if (!pass.equals(conf))       { confirm.setError("Passwords do not match"); return; }
        if (!"Strong".equals(currentStatus)) {
            password.setError("Password must be Strong (8 chars, upper, lower, number, symbol)");
            return;
        }

        if (!sign_btn.isEnabled()) return;
        sign_btn.setEnabled(false);

        final String authEmail  = userInput;
        final String normEmail  = authEmail.toLowerCase(Locale.ROOT);

        // ── Step 1: Check email index in Firestore FIRST ─────────────────
        //    This catches accounts created via Google/Facebook with the
        //    same email — Firebase Auth alone wouldn't catch those.
        db.collection("emails").document(normEmail).get()
                .addOnSuccessListener(emailDoc -> {
                    if (emailDoc.exists() && emailDoc.getString("uid") != null) {
                        sign_btn.setEnabled(true);
                        username.setError("This email is already registered.");
                        username.requestFocus();
                        Toast.makeText(this,
                                "An account with this email already exists. Please log in instead.",
                                Toast.LENGTH_LONG).show();
                    } else {
                        // ✅ Email is free — proceed to Firebase Auth
                        createFirebaseAccount(authEmail, normEmail, pass, name);
                    }
                })
                .addOnFailureListener(e -> {
                    // Firestore lookup failed — fall through to Firebase Auth
                    // which has its own "email already in use" error as a
                    // second line of defence.
                    createFirebaseAccount(authEmail, normEmail, pass, name);
                });
    }

    // ── Step 2: Create the Firebase Auth account ──────────────────────────
    private void createFirebaseAccount(String authEmail, String normEmail,
                                       String pass, String name) {
        auth.createUserWithEmailAndPassword(authEmail, pass)
                .addOnCompleteListener(task -> {
                    if (!task.isSuccessful()) {
                        sign_btn.setEnabled(true);
                        String msg = task.getException() != null
                                ? task.getException().getMessage() : "Unknown error";

                        // Firebase second-line defence for duplicate emails
                        if (msg != null && msg.toLowerCase().contains("already in use")) {
                            username.setError("This email is already registered.");
                            Toast.makeText(this,
                                    "An account with this email already exists.",
                                    Toast.LENGTH_LONG).show();
                        } else {
                            Toast.makeText(this,
                                    "Registration failed: " + msg, Toast.LENGTH_LONG).show();
                        }
                        return;
                    }

                    FirebaseUser user = auth.getCurrentUser();
                    if (user == null) {
                        sign_btn.setEnabled(true);
                        Toast.makeText(this,
                                "Registration failed: user is null", Toast.LENGTH_LONG).show();
                        return;
                    }

                    // ── Step 3: Write Firestore user document + email index ──
                    saveUserToFirestore(user.getUid(), authEmail, normEmail, name);
                });
    }

    // ── Step 3: Write user doc + email index atomically ───────────────────
    private void saveUserToFirestore(String uid, String authEmail,
                                     String normEmail, String name) {

        // Split fullname into first/last for compatibility with Login.java
        String[] parts     = name.trim().split(" ", 2);
        String   firstName = parts[0];
        String   lastName  = parts.length > 1 ? parts[1] : "";

        Map<String, Object> userData = new HashMap<>();
        userData.put("fullname",   name);
        userData.put("firstName",  firstName);
        userData.put("lastName",   lastName);
        userData.put("username",   authEmail);
        userData.put("authEmail",  authEmail);
        userData.put("email",      normEmail);
        userData.put("providers",  Arrays.asList("password"));
        userData.put("createdAt",  FieldValue.serverTimestamp());
        userData.put("lastLogin",  FieldValue.serverTimestamp());

        // Write user document
        db.collection("users").document(uid)
                .set(userData)
                .addOnSuccessListener(unused -> {
                    // Write email index — enforces uniqueness for social logins
                    db.collection("emails").document(normEmail)
                            .set(Map.of("uid", uid), SetOptions.merge())
                            .addOnSuccessListener(v -> sendWelcome(uid, authEmail, name))
                            .addOnFailureListener(e -> {
                                // User doc written but index failed — still continue
                                sendWelcome(uid, authEmail, name);
                            });
                })
                .addOnFailureListener(e -> {
                    sign_btn.setEnabled(true);
                    Toast.makeText(this,
                            "Firestore save failed: " + e.getMessage(), Toast.LENGTH_LONG).show();
                });
    }

    // ══════════════════════════════════════════════════════════════════════
    // WELCOME EMAIL via local server
    // ══════════════════════════════════════════════════════════════════════

    private void sendWelcome(String uid, String email, String name) {
        try {
            JSONObject json = new JSONObject();
            json.put("uid",         uid);
            json.put("channel",     "email");
            json.put("destination", email);
            json.put("fullName",    name);
            json.put("message",     "Welcome to BrewPOS, " + name
                    + "! Your account has been created.");

            RequestBody body = RequestBody.create(
                    json.toString(),
                    MediaType.parse("application/json"));

            Request request = new Request.Builder()
                    .url(BASE_URL + "/api/notify/welcome")
                    .post(body)
                    .build();

            httpClient.newCall(request).enqueue(new Callback() {
                @Override
                public void onFailure(Call call, IOException e) {
                    runOnUiThread(() -> {
                        sign_btn.setEnabled(true);
                        // Registration succeeded even if email notification fails
                        Toast.makeText(Signup.this,
                                "Registered! (Welcome email could not be sent)",
                                Toast.LENGTH_LONG).show();
                        goToLogin();
                    });
                }

                @Override
                public void onResponse(Call call, Response response) {
                    runOnUiThread(() -> {
                        sign_btn.setEnabled(true);
                        Toast.makeText(Signup.this,
                                "Registration successful!", Toast.LENGTH_LONG).show();
                        goToLogin();
                    });
                }
            });

        } catch (Exception e) {
            sign_btn.setEnabled(true);
            Toast.makeText(this,
                    "Message error: " + e.getMessage(), Toast.LENGTH_LONG).show();
            goToLogin();
        }
    }

    private void goToLogin() {
        startActivity(new Intent(Signup.this, Login.class));
        finish();
    }

    // ══════════════════════════════════════════════════════════════════════
    // HELPERS
    // ══════════════════════════════════════════════════════════════════════

    private boolean isEmail(String input) {
        return Patterns.EMAIL_ADDRESS.matcher(input).matches();
    }

    private void checkPasswordStrength(String pass) {
        if (pass.isEmpty()) {
            status.setText("Empty");
            status.setTextColor(Color.GRAY);
            currentStatus = "Empty";
            return;
        }
        if (pass.length() < 6) {
            status.setText("Weak");
            status.setTextColor(Color.RED);
            currentStatus = "Weak";
            return;
        }

        boolean hasUpper  = pass.matches(".*[A-Z].*");
        boolean hasLower  = pass.matches(".*[a-z].*");
        boolean hasNumber = pass.matches(".*[0-9].*");
        boolean hasSymbol = pass.matches(".*[@#$%^&+=!].*");

        if (hasUpper && hasLower && hasNumber && hasSymbol && pass.length() >= 8) {
            status.setText("Strong");
            status.setTextColor(Color.GREEN);
            currentStatus = "Strong";
        } else if (hasUpper && hasLower && hasNumber) {
            status.setText("Medium");
            status.setTextColor(Color.parseColor("#FFA500"));
            currentStatus = "Medium";
        } else {
            status.setText("Weak");
            status.setTextColor(Color.RED);
            currentStatus = "Weak";
        }
    }
}