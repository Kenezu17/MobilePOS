package com.brewpos.backend.controller;

import com.brewpos.backend.dto.ForgotPasswordRequest;
import com.brewpos.backend.dto.WelcomeRequest;
import com.brewpos.backend.service.NotifyService;
import com.google.firebase.auth.FirebaseAuthException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import com.google.firebase.auth.FirebaseAuth;

import java.util.Map;

@RestController
@RequestMapping("/api/notify")
public class NotifyController {

    private final NotifyService notifyService;

    public NotifyController(NotifyService notifyService) {
        this.notifyService = notifyService;
    }

    @PostMapping("/welcome")
    public ResponseEntity<?> welcome(@RequestBody WelcomeRequest req) {
        if (req == null || req.channel == null || req.destination == null) {
            return ResponseEntity.badRequest()
                    .body(Map.of("ok", false, "error", "Missing channel and destination"));
        }

        try {
            if ("email".equalsIgnoreCase(req.channel)) {
                // ✅ now passes fullName for the greeting
                notifyService.sendWelcomeEmail(req.destination, req.fullName);
            } else {
                return ResponseEntity.badRequest()
                        .body(Map.of("ok", false, "error", "Invalid channel"));
            }
            return ResponseEntity.ok(Map.of("ok", true, "sent", true));
        } catch (Exception e) {
            return ResponseEntity.status(500)
                    .body(Map.of("ok", false, "error", e.getMessage()));
        }
    }

    @PostMapping("/forgot-password")
    public ResponseEntity<?> forgotPassword(@RequestBody ForgotPasswordRequest req) {
        if (req == null || req.email == null || req.email.isEmpty()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("ok", false, "error", "Email is required"));
        }

        try {
            // ── Generate Firebase password reset link ─────────────────────
            String resetLink = FirebaseAuth.getInstance()
                    .generatePasswordResetLink(req.email);

            // ── Null guard ────────────────────────────────────────────────
            if (resetLink == null || resetLink.isBlank()) {
                return ResponseEntity.status(500)
                        .body(Map.of("ok", false, "error",
                                "Could not generate reset link. Email may not exist in Firebase."));
            }

            notifyService.sendPasswordResetEmail(req.email, resetLink);
            return ResponseEntity.ok(Map.of("ok", true, "sent", true));

        } catch (FirebaseAuthException e) {
            // ── Firebase-specific errors ──────────────────────────────────
            String msg = switch (e.getAuthErrorCode().name()) {
                case "EMAIL_NOT_FOUND"  -> "No account found with this email.";
                case "INVALID_EMAIL"    -> "Invalid email address.";
                case "USER_DISABLED"    -> "This account has been disabled.";
                default -> "Firebase error: " + e.getMessage();
            };
            return ResponseEntity.status(404)
                    .body(Map.of("ok", false, "error", msg));

        } catch (Exception e) {
            return ResponseEntity.status(500)
                    .body(Map.of("ok", false, "error", e.getMessage()));
        }
    }
}