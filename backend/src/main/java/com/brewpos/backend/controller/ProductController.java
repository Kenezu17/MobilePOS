package com.brewpos.backend.controller;

import com.brewpos.backend.dto.ChangePasswordRequest;
import com.brewpos.backend.dto.InventoryUpdateRequest;
import com.brewpos.backend.dto.ProductCreateRequest;
import com.brewpos.backend.dto.ProductUpdateRequest;
import com.brewpos.backend.service.ProductService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.Map;

@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class ProductController {

    private final ProductService service;

    public ProductController(ProductService service) {
        this.service = service;
    }

    private String uid(String header) {
        if (header == null || header.isBlank()) {
            throw new RuntimeException("Missing X-User-Id header");
        }
        return header.trim();
    }

    // ---------- PRODUCTS ----------

    @GetMapping("/products")
    public ResponseEntity<?> getProducts(
            @RequestHeader("X-User-Id") String userId) throws Exception {
        return ResponseEntity.ok(service.getProducts(uid(userId)));
    }

    @PostMapping("/products")
    public ResponseEntity<?> createProduct(
            @RequestHeader("X-User-Id") String userId,
            @RequestBody ProductCreateRequest req) throws Exception {
        String id = service.createProduct(uid(userId), req);
        return ResponseEntity.ok(Map.of("ok", true, "id", id));
    }

    @PutMapping("/products/{id}")
    public ResponseEntity<?> updateProduct(
            @RequestHeader("X-User-Id") String userId,
            @PathVariable String id,
            @RequestBody ProductUpdateRequest req) throws Exception {
        service.updateProduct(uid(userId), id, req);
        return ResponseEntity.ok(Map.of("ok", true));
    }

    @DeleteMapping("/products/{id}")
    public ResponseEntity<?> deleteProduct(
            @RequestHeader("X-User-Id") String userId,
            @PathVariable String id) throws Exception {
        service.deleteProduct(uid(userId), id);
        return ResponseEntity.ok(Map.of("ok", true));
    }

    @PostMapping(value = "/products/image", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> uploadProductImage(
            @RequestParam("file") MultipartFile file,
            HttpServletRequest request) throws Exception {
        String baseUrl = request.getScheme() + "://"
                + request.getServerName() + ":" + request.getServerPort();
        String imageUrl = service.removeBgAndSaveLocal(file, baseUrl);
        return ResponseEntity.ok(Map.of("ok", true, "imageUrl", imageUrl));
    }

    // ---------- INVENTORY ----------

    @GetMapping("/inventory")
    public ResponseEntity<?> getInventory(
            @RequestHeader("X-User-Id") String userId) throws Exception {
        return ResponseEntity.ok(service.getInventoryView(uid(userId)));
    }

    @PutMapping("/inventory/{productId}")
    public ResponseEntity<?> updateInventory(
            @RequestHeader("X-User-Id") String userId,
            @PathVariable String productId,
            @RequestBody InventoryUpdateRequest req) throws Exception {
        service.updateInventory(uid(userId), productId, req);
        return ResponseEntity.ok(Map.of("ok", true));
    }

    @PostMapping("/inventory/{productId}/adjust")
    public ResponseEntity<?> adjustStock(
            @RequestHeader("X-User-Id") String userId,
            @PathVariable String productId,
            @RequestParam int delta) throws Exception {
        service.adjustStock(uid(userId), productId, delta);
        return ResponseEntity.ok(Map.of("ok", true));
    }

    @DeleteMapping("/inventory/{productId}")
    public ResponseEntity<?> deleteInventory(
            @RequestHeader("X-User-Id") String userId,
            @PathVariable String productId) throws Exception {
        service.deleteInventory(uid(userId), productId);
        return ResponseEntity.ok(Map.of("ok", true));
    }

    // ---------- PROFILE ----------

    @PostMapping(value = "/profile/image", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> uploadProfileImage(
            @RequestParam("file") MultipartFile file,
            HttpServletRequest request) throws Exception {
        String baseUrl = request.getScheme() + "://"
                + request.getServerName() + ":" + request.getServerPort();
        String imageUrl = service.saveImageLocal(file, baseUrl);
        return ResponseEntity.ok(Map.of("ok", true, "imageUrl", imageUrl));
    }

    // ---------- AUTH ----------

    // PUT /api/auth/change-password
    // Called by the Flutter app AFTER Firebase Auth has already updated the password.
    // Firebase is the source of truth — this endpoint just syncs the local server.
    // Returns 200 on success, 400 if validation fails, 500 on unexpected error.
    @PutMapping("/auth/change-password")
    public ResponseEntity<?> changePassword(
            @RequestHeader("X-User-Id") String userId,
            @RequestBody ChangePasswordRequest req) {

        // Basic validation
        if (req.getNewPassword() == null || req.getNewPassword().length() < 6) {
            return ResponseEntity.badRequest()
                    .body(Map.of("ok", false, "error", "New password must be at least 6 characters"));
        }

        // At this point Firebase has already verified the old password and updated it.
        // Add any local sync logic here (e.g. update a local user record/cache).
        // Example: service.syncPasswordChange(uid(userId), req.getNewPassword());

        return ResponseEntity.ok(Map.of("ok", true, "message", "Password synced"));
    }
}