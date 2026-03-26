package com.example.pos;

import android.annotation.TargetApi;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.*;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;

import com.airbnb.lottie.LottieAnimationView;
import com.facebook.*;
import com.facebook.login.LoginManager;
import com.facebook.login.LoginResult;
import com.google.android.gms.auth.api.signin.*;
import com.google.android.gms.common.api.ApiException;
import com.google.firebase.auth.*;
import com.google.firebase.firestore.FieldValue;
import com.google.firebase.firestore.FirebaseFirestore;
import com.google.firebase.firestore.SetOptions;

import org.json.JSONObject;

import java.io.IOException;
import java.util.*;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

public class Login extends AppCompatActivity {

    private static final String TAG = "LOGIN_AUTH";

    // ── Views ──────────────────────────────────────────────────────────────
    private TextView            signup_btn;
    private Button              login_btn;
    private LottieAnimationView lottieloading;
    private EditText            username, password;
    private ImageButton         goggle, facebook;

    // ── Firebase ───────────────────────────────────────────────────────────
    private FirebaseAuth      auth;
    private FirebaseFirestore db;

    // ── Google ─────────────────────────────────────────────────────────────
    private GoogleSignInClient             googleClient;
    private ActivityResultLauncher<Intent> googleLauncher;

    // ── Facebook ───────────────────────────────────────────────────────────
    private CallbackManager fbCallbackManager;

    // ── HTTP (welcome email) ───────────────────────────────────────────────
    private final OkHttpClient httpClient = new OkHttpClient();

    // ─────────────────────────────────────────────────────────────────────
    // ✅ Replace 192.168.x.x with your computer's actual local IP.
    //    Find it with:  Windows → ipconfig   |   Mac/Linux → hostname -I
    //    Your phone and computer must be on the same Wi-Fi network.
    //    127.0.0.1 only works on an emulator, NOT on a physical device.
    // ─────────────────────────────────────────────────────────────────────
    private static final String BASE_URL = "http://127.0.0.1:8081";

    // ══════════════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ══════════════════════════════════════════════════════════════════════

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.login);

        auth = FirebaseAuth.getInstance();
        db   = FirebaseFirestore.getInstance();

        signup_btn    = findViewById(R.id.signup2);
        login_btn     = findViewById(R.id.signin_btn);
        lottieloading = findViewById(R.id.lottie_loading);
        username      = findViewById(R.id.email);
        password      = findViewById(R.id.password);
        goggle        = findViewById(R.id.google);
        facebook      = findViewById(R.id.facebook);

        signup_btn.setOnClickListener(v ->
                startActivity(new Intent(Login.this, Signup.class)));
        login_btn.setOnClickListener(v -> emailPasswordLogin());

        TextView forgotPassword = findViewById(R.id.forgetpass);
        forgotPassword.setOnClickListener(v ->
                startActivity(new Intent(Login.this, ForgotPasswordActivity.class))
        );

        setupGoogle();
        setupFacebook();
    }

    // ══════════════════════════════════════════════════════════════════════
    // 1. EMAIL / PASSWORD LOGIN
    // ══════════════════════════════════════════════════════════════════════

    private void emailPasswordLogin() {
        String email = username.getText().toString().trim();
        String pass  = password.getText().toString().trim();

        if (email.isEmpty()) { username.setError("Email required"); return; }
        if (pass.isEmpty())  { password.setError("Password required"); return; }

        startLoading();
        auth.signInWithEmailAndPassword(email, pass)
                .addOnSuccessListener(result -> {
                    FirebaseUser user = result.getUser();
                    openMain();
                    // Fire-and-forget: update lastLogin only — never overwrite existing data.
                    db.collection("users").document(user.getUid())
                            .set(Map.of(
                                    "lastLogin", FieldValue.serverTimestamp(),
                                    "providers", FieldValue.arrayUnion("password")
                            ), SetOptions.merge())
                            .addOnFailureListener(e ->
                                    Log.w(TAG, "lastLogin update failed (non-fatal)", e));
                })
                .addOnFailureListener(e -> {
                    stopLoading();
                    Log.e(TAG, "Email login failed", e);
                    Toast.makeText(this, friendlyAuthError(e), Toast.LENGTH_LONG).show();
                });
    }

    // ══════════════════════════════════════════════════════════════════════
    // 2. GOOGLE
    // ══════════════════════════════════════════════════════════════════════

    private void setupGoogle() {
        GoogleSignInOptions gso = new GoogleSignInOptions.Builder(
                GoogleSignInOptions.DEFAULT_SIGN_IN)
                .requestIdToken("762199211621-i91ddv4u05f37781sd2edc4ijugfqof3.apps.googleusercontent.com")
                .requestEmail()
                .build();

        googleClient = GoogleSignIn.getClient(this, gso);

        googleLauncher = registerForActivityResult(
                new ActivityResultContracts.StartActivityForResult(),
                result -> {
                    try {
                        GoogleSignInAccount account =
                                GoogleSignIn.getSignedInAccountFromIntent(result.getData())
                                        .getResult(ApiException.class);
                        if (account != null) {
                            String email   = account.getEmail();
                            String idToken = account.getIdToken();
                            AuthCredential credential =
                                    GoogleAuthProvider.getCredential(idToken, null);
                            String[] names = splitName(account.getDisplayName());
                            String   photo = account.getPhotoUrl() != null
                                    ? account.getPhotoUrl().toString() : "";

                            handleSocialLogin(email, credential, "google",
                                    names[0], names[1], photo);
                        }
                    } catch (ApiException e) {
                        stopLoading();
                        Log.e(TAG, "Google sign-in failed, code=" + e.getStatusCode(), e);
                        Toast.makeText(this,
                                "Google sign-in failed (code " + e.getStatusCode() + ")."
                                        + " Verify SHA-1 in Firebase console.",
                                Toast.LENGTH_LONG).show();
                    } catch (Exception e) {
                        stopLoading();
                        Log.e(TAG, "Google unexpected error", e);
                        Toast.makeText(this, "Google sign-in error: " + e.getMessage(),
                                Toast.LENGTH_LONG).show();
                    }
                });

        goggle.setOnClickListener(v -> {
            startLoading();
            googleLauncher.launch(googleClient.getSignInIntent());
        });
    }

    // ══════════════════════════════════════════════════════════════════════
    // 3. FACEBOOK
    // ══════════════════════════════════════════════════════════════════════

    private void setupFacebook() {
        fbCallbackManager = CallbackManager.Factory.create();
        LoginManager.getInstance().registerCallback(fbCallbackManager,
                new FacebookCallback<LoginResult>() {
                    @Override public void onSuccess(LoginResult r) {
                        startLoading();
                        fetchFacebookProfile(r.getAccessToken(), (first, last, photo, email) -> {
                            AuthCredential credential =
                                    FacebookAuthProvider.getCredential(
                                            r.getAccessToken().getToken());
                            handleSocialLogin(email, credential, "facebook",
                                    first, last, photo);
                        });
                    }
                    @Override public void onCancel() {
                        stopLoading();
                        Toast.makeText(Login.this, "Cancelled", Toast.LENGTH_SHORT).show();
                    }
                    @Override public void onError(@NonNull FacebookException e) {
                        stopLoading();
                        Toast.makeText(Login.this,
                                "Facebook error: " + e.getMessage(), Toast.LENGTH_LONG).show();
                    }
                });

        facebook.setOnClickListener(v ->
                LoginManager.getInstance().logInWithReadPermissions(
                        Login.this, Arrays.asList("public_profile", "email")));
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (fbCallbackManager != null) fbCallbackManager.onActivityResult(req, res, data);
    }

    // ══════════════════════════════════════════════════════════════════════
    // 4. CORE: EMAIL-BASED SOCIAL LOGIN ROUTING
    // ══════════════════════════════════════════════════════════════════════

    private void handleSocialLogin(String email,
                                   AuthCredential credential,
                                   String provider,
                                   String first, String last, String photo) {

        if (email == null || email.isEmpty()) {
            Log.w(TAG, provider + " returned no email — skipping dedup check");
            signInDirectly(credential, provider, first, last, photo);
            return;
        }

        String normEmail = email.toLowerCase(Locale.ROOT);

        db.collection("emails").document(normEmail).get()
                .addOnSuccessListener(emailDoc -> {
                    if (emailDoc.exists() && emailDoc.getString("uid") != null) {
                        // ── Existing account: link provider, merge fields, NO welcome email ──
                        String existingUid = emailDoc.getString("uid");
                        Log.d(TAG, "Email already registered (uid=" + existingUid
                                + "). Linking " + provider);
                        linkProviderToExistingAccount(
                                existingUid, credential, provider, first, last, photo);
                    } else {
                        // ── New account: create + send welcome email ──
                        Log.d(TAG, "New email. Creating account via " + provider);
                        signInDirectly(credential, provider, first, last, photo);
                    }
                })
                .addOnFailureListener(e -> {
                    Log.e(TAG, "Email index lookup failed; attempting direct sign-in", e);
                    signInDirectly(credential, provider, first, last, photo);
                });
    }

    // ── Path A: returning user — link new provider, merge only missing fields
    //            NO welcome email sent (account already exists)
    private void linkProviderToExistingAccount(String existingUid,
                                               AuthCredential newCredential,
                                               String provider,
                                               String first, String last, String photo) {
        auth.signInWithCredential(newCredential)
                .addOnSuccessListener(result -> {
                    FirebaseUser firebaseUser = result.getUser();

                    if (!firebaseUser.getUid().equals(existingUid)) {
                        Log.w(TAG, "UID mismatch! Firestore=" + existingUid
                                + " Firebase=" + firebaseUser.getUid()
                                + ". Correcting email index.");
                        db.collection("emails").document(
                                        firebaseUser.getEmail() != null
                                                ? firebaseUser.getEmail().toLowerCase(Locale.ROOT)
                                                : firebaseUser.getUid())
                                .set(Map.of("uid", firebaseUser.getUid()), SetOptions.merge());
                    }

                    firebaseUser.linkWithCredential(newCredential)
                            .addOnCompleteListener(linkTask -> {
                                if (!linkTask.isSuccessful()) {
                                    Log.d(TAG, "linkWithCredential (expected if already linked): "
                                            + (linkTask.getException() != null
                                            ? linkTask.getException().getMessage() : "ok"));
                                }
                                // Returning user — go straight to app, no welcome email
                                openMain();
                                mergeMissingFields(firebaseUser.getUid(),
                                        provider, first, last, photo);
                            });
                })
                .addOnFailureListener(e -> {
                    stopLoading();
                    Log.e(TAG, "signInWithCredential failed during link flow", e);
                    Toast.makeText(this, friendlyAuthError(e), Toast.LENGTH_LONG).show();
                });
    }

    // ── Path B: brand-new account — write Firestore, send welcome email, navigate
    private void signInDirectly(AuthCredential credential,
                                String provider,
                                String first, String last, String photo) {
        auth.signInWithCredential(credential)
                .addOnSuccessListener(result -> {
                    FirebaseUser user = result.getUser();
                    // DO NOT call openMain() here — navigation happens inside
                    // sendWelcome() after the HTTP call completes (or fails).
                    createNewUserInFirestore(user, provider, first, last, photo);
                })
                .addOnFailureListener(e -> {
                    stopLoading();
                    Log.e(TAG, "signInWithCredential failed", e);
                    Toast.makeText(this, friendlyAuthError(e), Toast.LENGTH_LONG).show();
                });
    }

    // ══════════════════════════════════════════════════════════════════════
    // 5. FIRESTORE WRITE HELPERS
    // ══════════════════════════════════════════════════════════════════════

    /**
     * New social account:
     *   1. Write user document to users/{uid}
     *   2. Write email index to emails/{email}
     *   3. Send welcome email → then navigate to MainActivity
     */
    private void createNewUserInFirestore(FirebaseUser user,
                                          String provider,
                                          String first, String last, String photo) {
        String uid      = user.getUid();
        String email    = user.getEmail() != null
                ? user.getEmail().toLowerCase(Locale.ROOT) : "";
        String fullname = (first + " " + last).trim();

        Map<String, Object> userData = new HashMap<>();
        if (!first.isEmpty())    userData.put("firstName", first);
        if (!last.isEmpty())     userData.put("lastName",  last);
        if (!photo.isEmpty())    userData.put("photoUrl",  photo);
        if (!email.isEmpty())    userData.put("email",     email);
        if (!fullname.isEmpty()) userData.put("fullname",  fullname);

        userData.put("providers", Arrays.asList(provider));
        userData.put("createdAt", FieldValue.serverTimestamp());
        userData.put("lastLogin", FieldValue.serverTimestamp());

        db.collection("users").document(uid)
                .set(userData)
                .addOnSuccessListener(v -> {
                    Log.d(TAG, "New social user written uid=" + uid);

                    // Write email index (non-blocking, non-fatal)
                    if (!email.isEmpty()) {
                        db.collection("emails").document(email)
                                .set(Map.of("uid", uid), SetOptions.merge())
                                .addOnFailureListener(e ->
                                        Log.e(TAG, "Email index write failed (non-fatal)", e));
                    }

                    // Send welcome email → navigate on completion or failure
                    String displayName = fullname.isEmpty()
                            ? provider + " user" : fullname;
                    sendWelcome(uid, email, displayName);
                })
                .addOnFailureListener(e -> {
                    Log.e(TAG, "Failed to write new social user to Firestore", e);
                    // Firebase Auth succeeded — navigate anyway
                    openMain();
                });
    }

    /**
     * Returning user: only fill Firestore fields that are currently blank.
     * Existing name / photo / password data is NEVER overwritten.
     */
    private void mergeMissingFields(String uid,
                                    String provider,
                                    String first, String last, String photo) {
        db.collection("users").document(uid).get()
                .addOnSuccessListener(doc -> {
                    Map<String, Object> updates = new HashMap<>();

                    if (shouldFill(doc.getString("firstName"), first))
                        updates.put("firstName", first);
                    if (shouldFill(doc.getString("lastName"), last))
                        updates.put("lastName", last);
                    if (shouldFill(doc.getString("photoUrl"), photo))
                        updates.put("photoUrl", photo);

                    if (updates.containsKey("firstName") || updates.containsKey("lastName")) {
                        String resolvedFirst = updates.containsKey("firstName") ? first
                                : (doc.getString("firstName") != null
                                ? doc.getString("firstName") : "");
                        String resolvedLast  = updates.containsKey("lastName")  ? last
                                : (doc.getString("lastName")  != null
                                ? doc.getString("lastName")  : "");
                        if (!resolvedFirst.isEmpty() || !resolvedLast.isEmpty())
                            updates.put("fullname",
                                    (resolvedFirst + " " + resolvedLast).trim());
                    }

                    updates.put("lastLogin", FieldValue.serverTimestamp());
                    updates.put("providers", FieldValue.arrayUnion(provider));

                    db.collection("users").document(uid)
                            .set(updates, SetOptions.merge())
                            .addOnSuccessListener(v ->
                                    Log.d(TAG, "Returning user merged uid=" + uid))
                            .addOnFailureListener(e ->
                                    Log.e(TAG, "Returning user merge failed", e));
                })
                .addOnFailureListener(e -> {
                    Log.e(TAG, "Could not read doc for merge; writing safe fields only", e);
                    db.collection("users").document(uid)
                            .set(Map.of(
                                    "lastLogin", FieldValue.serverTimestamp(),
                                    "providers", FieldValue.arrayUnion(provider)
                            ), SetOptions.merge());
                });
    }

    private boolean shouldFill(String existing, String candidate) {
        return (existing == null || existing.isEmpty())
                && (candidate != null && !candidate.isEmpty());
    }

    // ══════════════════════════════════════════════════════════════════════
    // 6. WELCOME EMAIL  ←  NEW: fires only for brand-new social accounts
    // ══════════════════════════════════════════════════════════════════════

    /**
     * POSTs a welcome notification to the local server.
     * Navigation to MainActivity always happens — on both success and failure —
     * so the user is never stuck on the login screen.
     */
    private void sendWelcome(String uid, String email, String fullName) {
        try {
            JSONObject json = new JSONObject();
            json.put("uid",         uid);
            json.put("channel",     "email");
            json.put("destination", email);
            json.put("fullName",    fullName);
            json.put("message",     "Welcome to BrewPOS, " + fullName
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
                    Log.w(TAG, "Welcome email failed (non-fatal): " + e.getMessage());
                    runOnUiThread(() -> openMain());  // Navigate anyway
                }

                @Override
                public void onResponse(Call call, Response response) {
                    Log.d(TAG, "Welcome email sent. HTTP " + response.code());
                    runOnUiThread(() -> openMain());  // Navigate after success
                }
            });

        } catch (Exception e) {
            Log.e(TAG, "sendWelcome exception: " + e.getMessage());
            openMain();  // Never leave the user stuck
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // 7. FACEBOOK PROFILE FETCH
    // ══════════════════════════════════════════════════════════════════════

    private interface FacebookProfileCallback {
        void onResult(String first, String last, String photoUrl, String email);
    }

    private void fetchFacebookProfile(AccessToken token, FacebookProfileCallback cb) {
        GraphRequest request = GraphRequest.newMeRequest(token, (object, response) -> {
            if (response.getError() != null || object == null) {
                cb.onResult("", "", "", "");
                return;
            }
            String first = object.optString("first_name", "");
            String last  = object.optString("last_name",  "");
            String email = object.optString("email",      "");
            String photo = "";
            try {
                photo = object.getJSONObject("picture")
                        .getJSONObject("data").optString("url", "");
            } catch (Exception ignored) {}
            cb.onResult(first, last, photo, email);
        });
        Bundle params = new Bundle();
        params.putString("fields",
                "id,first_name,last_name,email,picture.type(large)");
        request.setParameters(params);
        request.executeAsync();
    }

    // ══════════════════════════════════════════════════════════════════════
    // 8. NAVIGATION
    // ══════════════════════════════════════════════════════════════════════

    private void openMain() {
        startActivity(new Intent(Login.this, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                        | Intent.FLAG_ACTIVITY_CLEAR_TASK));
        finish();
    }

    // ══════════════════════════════════════════════════════════════════════
    // 9. UI HELPERS
    // ══════════════════════════════════════════════════════════════════════

    private void startLoading() {
        login_btn.setEnabled(false);
        lottieloading.setVisibility(View.VISIBLE);
        lottieloading.playAnimation();
    }

    private void stopLoading() {
        login_btn.setEnabled(true);
        lottieloading.cancelAnimation();
        lottieloading.setVisibility(View.GONE);
    }

    private String[] splitName(String full) {
        if (full == null || full.isEmpty()) return new String[]{"", ""};
        String[] parts = full.split(" ");
        return new String[]{
                parts[0],
                parts.length > 1 ? parts[parts.length - 1] : ""
        };
    }

    private String friendlyAuthError(Exception e) {
        String code = e instanceof FirebaseAuthException
                ? ((FirebaseAuthException) e).getErrorCode() : "";
        if (code.contains("invalid-credential")
                || code.contains("wrong-password")
                || code.contains("user-not-found"))
            return "Incorrect email or password.";
        if (code.contains("invalid-email"))
            return "Please enter a valid email address.";
        if (code.contains("too-many-requests"))
            return "Too many attempts. Please wait and try again.";
        if (code.contains("network-request-failed"))
            return "No internet connection.";
        if (code.contains("account-exists-with-different-credential"))
            return "An account already exists with this email. Try a different sign-in method.";
        return "Authentication failed: " + e.getMessage();
    }
}