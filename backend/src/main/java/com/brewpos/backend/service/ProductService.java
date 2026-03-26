package com.brewpos.backend.service;

import com.brewpos.backend.dto.InventoryUpdateRequest;
import com.brewpos.backend.dto.ProductCreateRequest;
import com.brewpos.backend.dto.ProductUpdateRequest;
import com.google.cloud.firestore.*;
import com.google.firebase.cloud.FirestoreClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.ByteArrayOutputStream;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.*;

@Service
public class ProductService {

    private final Firestore db = FirestoreClient.getFirestore();

    @Value("${removebg.apiKey:}")
    private String removeBgApiKey;

    @Value("${app.upload.dir:uploads}")
    private String uploadDir;

    // ── Scoped collection helpers ─────────────────────────────────

    private CollectionReference products(String uid) {
        return db.collection("users").document(uid).collection("products");
    }

    private CollectionReference inventory(String uid) {
        return db.collection("users").document(uid).collection("inventory");
    }

    // ---------- PROFILE IMAGE ----------

    public String saveImageLocal(MultipartFile file, String baseUrl) throws Exception {
        if (file == null || file.isEmpty()) {
            throw new RuntimeException("File is empty");
        }

        Path dir = Paths.get(uploadDir).toAbsolutePath().normalize();
        Files.createDirectories(dir);

        String filename = "profile_" + System.currentTimeMillis()
                + "_" + UUID.randomUUID() + ".jpg";
        Path out = dir.resolve(filename);
        Files.write(out, file.getBytes());

        return "/uploads/" + filename;
    }

    // ---------- CREATE ----------

    public String createProduct(String uid, ProductCreateRequest req) throws Exception {
        DocumentReference productRef = products(uid).document();
        String productId = productRef.getId();

        Map<String, Object> product = new HashMap<>();
        product.put("name",      req.getName());
        product.put("section",   req.getSection());
        product.put("sellPrice", req.getSellPrice() != null ? req.getSellPrice() : 0);
        product.put("imageUrl",  req.getImageUrl()  != null ? req.getImageUrl()  : "");
        product.put("createdAt", FieldValue.serverTimestamp());
        product.put("updatedAt", FieldValue.serverTimestamp());

        productRef.set(product).get();
        return productId;
    }

    // ---------- PRODUCTS ----------

    public List<Map<String, Object>> getProducts(String uid) throws Exception {
        QuerySnapshot snap = products(uid)
                .orderBy("createdAt", Query.Direction.DESCENDING)
                .get().get();

        List<Map<String, Object>> out = new ArrayList<>();
        for (DocumentSnapshot d : snap.getDocuments()) {
            Map<String, Object> m = new HashMap<>(
                    Objects.requireNonNullElse(d.getData(), Map.of()));
            m.put("id", d.getId());
            out.add(m);
        }
        return out;
    }

    public void updateProduct(String uid, String productId, ProductUpdateRequest req) throws Exception {
        Map<String, Object> update = new HashMap<>();
        if (req.getName()      != null) update.put("name",      req.getName());
        if (req.getSection()   != null) update.put("section",   req.getSection());
        if (req.getSellPrice() != null) update.put("sellPrice", req.getSellPrice());
        if (req.getImageUrl()  != null) update.put("imageUrl",  req.getImageUrl());
        update.put("updatedAt", FieldValue.serverTimestamp());

        products(uid).document(productId).set(update, SetOptions.merge()).get();
    }

    public void deleteProduct(String uid, String productId) throws Exception {
        WriteBatch batch = db.batch();
        batch.delete(products(uid).document(productId));
        batch.delete(inventory(uid).document(productId));
        batch.commit().get();
    }

    // ---------- INVENTORY ----------

    public List<Map<String, Object>> getInventoryView(String uid) throws Exception {
        QuerySnapshot prodSnap = products(uid).get().get();
        Map<String, Map<String, Object>> productsById = new HashMap<>();
        for (DocumentSnapshot p : prodSnap.getDocuments()) {
            productsById.put(p.getId(),
                    new HashMap<>(Objects.requireNonNullElse(p.getData(), Map.of())));
        }

        QuerySnapshot invSnap = inventory(uid).get().get();
        List<Map<String, Object>> out = new ArrayList<>();

        for (DocumentSnapshot inv : invSnap.getDocuments()) {
            String productId = inv.getId();
            Map<String, Object> invData = new HashMap<>(
                    Objects.requireNonNullElse(inv.getData(), Map.of()));
            Map<String, Object> prod = productsById.get(productId);

            if (prod == null) continue;

            Long stockLong    = inv.getLong("stockQty");
            Long buyPriceLong = inv.getLong("buyPrice");
            long stock        = stockLong    != null ? stockLong    : 0L;
            long buyPrice     = buyPriceLong != null ? buyPriceLong : 0L;

            Map<String, Object> merged = new HashMap<>();
            merged.put("id",           productId);
            merged.put("productId",    productId);
            merged.put("name",         prod.getOrDefault("name",      ""));
            merged.put("section",      prod.getOrDefault("section",   ""));
            merged.put("sellPrice",    prod.getOrDefault("sellPrice", 0));
            merged.put("imageUrl",     prod.getOrDefault("imageUrl",  ""));
            merged.put("barcode",      invData.getOrDefault("barcode",      ""));
            merged.put("buyPrice",     invData.getOrDefault("buyPrice",     0));
            merged.put("stockQty",     invData.getOrDefault("stockQty",     0));
            merged.put("unit",         invData.getOrDefault("unit",         "pcs"));
            merged.put("reorderLevel", invData.getOrDefault("reorderLevel", 0));
            merged.put("totalBuyCost", stock * buyPrice);
            merged.put("updatedAt",    invData.getOrDefault("updatedAt",    null));

            out.add(merged);
        }

        out.sort(Comparator.comparing(m -> String.valueOf(m.getOrDefault("name", ""))));
        return out;
    }

    public void updateInventory(String uid, String productId, InventoryUpdateRequest req) throws Exception {
        Map<String, Object> update = new HashMap<>();
        if (req.getBarcode()      != null) update.put("barcode",      req.getBarcode());
        if (req.getBuyPrice()     != null) update.put("buyPrice",     req.getBuyPrice());
        if (req.getReorderLevel() != null) update.put("reorderLevel", req.getReorderLevel());
        if (req.getUnit()         != null) update.put("unit",         req.getUnit());
        if (req.getStockQty()     != null) update.put("stockQty",     Math.max(0, req.getStockQty()));
        update.put("updatedAt", FieldValue.serverTimestamp());

        inventory(uid).document(productId).set(update, SetOptions.merge()).get();
    }

    public void deleteInventory(String uid, String productId) throws Exception {
        inventory(uid).document(productId).delete().get();
    }

    public void adjustStock(String uid, String productId, int delta) throws Exception {
        DocumentReference invRef = inventory(uid).document(productId);
        db.runTransaction(tx -> {
            DocumentSnapshot snap = tx.get(invRef).get();
            long current = snap.exists() && snap.getLong("stockQty") != null
                    ? snap.getLong("stockQty") : 0L;
            long updated = Math.max(0, current + delta);

            Map<String, Object> update = new HashMap<>();
            update.put("stockQty",  updated);
            update.put("updatedAt", FieldValue.serverTimestamp());
            tx.set(invRef, update, SetOptions.merge());
            return null;
        }).get();
    }

    // ---------- REMOVE.BG + SAVE LOCAL ----------

    public String removeBgAndSaveLocal(MultipartFile file, String baseUrl) throws Exception {
        if (file == null || file.isEmpty()) {
            throw new RuntimeException("File is empty");
        }

        // ── Step 1: Always save the original file first ───────────
        Path dir = Paths.get(uploadDir).toAbsolutePath().normalize();
        Files.createDirectories(dir);

        String originalFilename = "orig_" + System.currentTimeMillis()
                + "_" + UUID.randomUUID() + ".jpg";
        Path originalPath = dir.resolve(originalFilename);
        Files.write(originalPath, file.getBytes());

        String originalRelUrl = "/uploads/" + originalFilename;

        // ── Step 2: Check if remove.bg is enabled ─────────────────
        boolean removeBgEnabled = removeBgApiKey != null
                && !removeBgApiKey.isBlank()
                && !removeBgApiKey.equals("0");

        if (!removeBgEnabled) {
            System.out.println("[removeBg] Skipped — API key not set (returning original).");
            return originalRelUrl;
        }

        // ── Step 3: Call remove.bg ────────────────────────────────
        try {
            byte[] pngBytes = callRemoveBg(file);

            String bgFilename = "nobg_" + System.currentTimeMillis()
                    + "_" + UUID.randomUUID() + ".png";
            Path bgPath = dir.resolve(bgFilename);
            Files.write(bgPath, pngBytes);

            System.out.println("[removeBg] Background removed successfully: " + bgFilename);

            // Delete the original since we have the bg-removed version
            Files.deleteIfExists(originalPath);

            return "/uploads/" + bgFilename;

        } catch (Exception e) {
            // ── Step 4: remove.bg failed — fall back to original ──
            System.err.println("[removeBg] Failed — falling back to original image. Reason: " + e.getMessage());
            return originalRelUrl;
        }
    }

    private byte[] callRemoveBg(MultipartFile file) throws Exception {
        HttpClient client   = HttpClient.newHttpClient();
        String     boundary = "----JavaBoundary" + System.currentTimeMillis();

        ByteArrayOutputStream bos    = new ByteArrayOutputStream();
        PrintWriter           writer = new PrintWriter(
                new OutputStreamWriter(bos, StandardCharsets.UTF_8), true);

        // ── size field ────────────────────────────────────────────
        writer.append("--").append(boundary).append("\r\n");
        writer.append("Content-Disposition: form-data; name=\"size\"\r\n\r\n");
        writer.append("preview").append("\r\n"); // ← FREE (was "auto" which costs credits)

        // ── image_file field ──────────────────────────────────────
        String filename = Optional.ofNullable(file.getOriginalFilename())
                .orElse("image.jpg");

        writer.append("--").append(boundary).append("\r\n");
        writer.append("Content-Disposition: form-data; name=\"image_file\"; filename=\"")
                .append(filename).append("\"\r\n");
        writer.append("Content-Type: application/octet-stream\r\n\r\n");
        writer.flush();

        bos.write(file.getBytes());
        bos.write("\r\n".getBytes(StandardCharsets.UTF_8));

        writer.append("--").append(boundary).append("--\r\n");
        writer.flush();

        HttpRequest request = HttpRequest.newBuilder()
                .uri(new URI("https://api.remove.bg/v1.0/removebg"))
                .header("X-Api-Key", removeBgApiKey)
                .header("Content-Type", "multipart/form-data; boundary=" + boundary)
                .POST(HttpRequest.BodyPublishers.ofByteArray(bos.toByteArray()))
                .build();

        HttpResponse<byte[]> response = client.send(request,
                HttpResponse.BodyHandlers.ofByteArray());

        if (response.statusCode() != 200) {
            throw new RuntimeException("remove.bg error: "
                    + new String(response.body(), StandardCharsets.UTF_8));
        }

        return response.body();
    }
}