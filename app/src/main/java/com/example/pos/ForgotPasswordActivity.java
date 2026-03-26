package com.example.pos;

import static androidx.core.content.ContextCompat.startActivity;

import android.content.Intent;
import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import java.net.HttpURLConnection;
import java.net.URL;

public class ForgotPasswordActivity extends AppCompatActivity {

    private EditText  emailInput;
    private Button    resetBtn;
    private TextView  backToLogin;

    // ── Change this to your actual backend base URL ───────────────────────
    private static final String BACKEND_URL =
            "http://127.0.0.1:8081/api/notify/forgot-password";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_forgot_password);

        emailInput  = findViewById(R.id.email_input);
        resetBtn    = findViewById(R.id.reset_btn);
        backToLogin = findViewById(R.id.back_to_login);

        // ── "Back to Login" link ──────────────────────────────────────────
        backToLogin.setOnClickListener(v -> {
            startActivity(new Intent(this, Login.class));
            finish();
        });

        // ── Send reset link button ────────────────────────────────────────
        resetBtn.setOnClickListener(v -> sendResetEmail());
    }

    private void sendResetEmail() {
        String email = emailInput.getText().toString().trim();

        // ── Validation ────────────────────────────────────────────────────
        if (email.isEmpty()) {
            emailInput.setError("Email is required");
            emailInput.requestFocus();
            return;
        }
        if (!android.util.Patterns.EMAIL_ADDRESS.matcher(email).matches()) {
            emailInput.setError("Enter a valid email address");
            emailInput.requestFocus();
            return;
        }

        // ── Disable button to prevent double-tap ──────────────────────────
        resetBtn.setEnabled(false);
        resetBtn.setText("Sending…");

        // ── Call Spring Boot backend on a background thread ───────────────
        new Thread(() -> {
            try {
                URL url = new URL(BACKEND_URL);
                HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                conn.setRequestMethod("POST");
                conn.setRequestProperty("Content-Type", "application/json");
                conn.setConnectTimeout(10_000); // 10 seconds
                conn.setReadTimeout(10_000);
                conn.setDoOutput(true);

                // Build JSON body
                String body = "{\"email\":\"" + email + "\"}";
                conn.getOutputStream().write(body.getBytes("UTF-8"));

                int responseCode = conn.getResponseCode();

                runOnUiThread(() -> {
                    if (responseCode == 200) {
                        // ── Success ───────────────────────────────────────
                        Toast.makeText(this,
                                "Reset link sent to " + email,
                                Toast.LENGTH_LONG).show();
                        startActivity(new Intent(this, Login.class));
                        finish();
                    } else if (responseCode == 404) {
                        // ── Email not found ───────────────────────────────
                        resetBtn.setEnabled(true);
                        resetBtn.setText("Send Reset Link");
                        Toast.makeText(this,
                                "Email not found. Please check your email.",
                                Toast.LENGTH_LONG).show();
                    } else if (responseCode == 429) {
                        // ── Too many requests ─────────────────────────────
                        resetBtn.setEnabled(true);
                        resetBtn.setText("Send Reset Link");
                        Toast.makeText(this,
                                "Too many attempts. Please wait and try again.",
                                Toast.LENGTH_LONG).show();
                    } else {
                        // ── Other server error ────────────────────────────
                        resetBtn.setEnabled(true);
                        resetBtn.setText("Send Reset Link");
                        Toast.makeText(this,
                                "Failed to send reset email. Please try again.",
                                Toast.LENGTH_LONG).show();
                    }
                });

            } catch (java.net.SocketTimeoutException e) {
                // ── Timeout ───────────────────────────────────────────────
                runOnUiThread(() -> {
                    resetBtn.setEnabled(true);
                    resetBtn.setText("Send Reset Link");
                    Toast.makeText(this,
                            "Request timed out. Check your connection.",
                            Toast.LENGTH_LONG).show();
                });
            } catch (Exception e) {
                // ── No internet / unknown error ───────────────────────────
                runOnUiThread(() -> {
                    resetBtn.setEnabled(true);
                    resetBtn.setText("Send Reset Link");
                    Toast.makeText(this,
                            "No internet connection.",
                            Toast.LENGTH_LONG).show();
                });
            }
        }).start();
    }
}