package com.brewpos.backend.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Set;

@Service
public class ImageService {

    @Value("${app.upload.dir}")
    private String uploadDir;

    private static final Set<String> ALLOWED = Set.of("jpg", "jpeg", "png", "webp");

    public String saveProductImage(MultipartFile file) throws Exception {
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("File is empty");
        }

        String original = file.getOriginalFilename() == null ? "image" : file.getOriginalFilename();
        String ext = getExt(original);

        if (!ALLOWED.contains(ext)) {
            throw new IllegalArgumentException("Unsupported file type: " + ext);
        }

        // Ensure folder exists
        Path dir = Paths.get(uploadDir).toAbsolutePath().normalize();
        Files.createDirectories(dir);

        // Create filename
        String filename = "product_" + System.currentTimeMillis() + "." + ext;
        Path target = dir.resolve(filename);

        // Save file
        Files.write(target, file.getBytes());

        return filename;
    }

    private String getExt(String name) {
        int i = name.lastIndexOf('.');
        if (i < 0) return "jpg";
        return name.substring(i + 1).toLowerCase();
    }
}