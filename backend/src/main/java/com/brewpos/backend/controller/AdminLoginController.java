package com.brewpos.backend.controller;

import com.brewpos.backend.service.AdminService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/admin")
public class AdminLoginController {

    private final AdminService adminService;

    public AdminLoginController(AdminService adminService) {
        this.adminService = adminService;
    }


    @GetMapping("/me")
    public ResponseEntity<?> me(HttpServletRequest request) throws Exception {
        String uid = (String) request.getAttribute("uid");
        String email = (String) request.getAttribute("email");

        if (uid == null) {
            return ResponseEntity.status(401).body(Map.of(
                    "ok", false,
                    "error", "Missing Authorization: Bearer <token>"
            ));
        }

        boolean isAdmin = adminService.isAdmin(uid);

        return ResponseEntity.ok(Map.of(
                "ok", true,
                "uid", uid,
                "email", email == null ? "" : email,
                "isAdmin", isAdmin
        ));
    }


    @PostMapping("/bootstrap")
    public ResponseEntity<?> bootstrap(HttpServletRequest request) throws Exception {
        String uid = (String) request.getAttribute("uid");
        String email = (String) request.getAttribute("email");

        if (uid == null) {
            return ResponseEntity.status(401).body(Map.of(
                    "ok", false,
                    "error", "Missing Authorization: Bearer <token>"
            ));
        }

        adminService.upsertAdmin(uid, email == null ? "" : email);

        return ResponseEntity.ok(Map.of(
                "ok", true,
                "message", "Admin user created/updated",
                "uid", uid,
                "email", email == null ? "" : email
        ));
    }
}