package com.brewpos.backend.service;

import jakarta.mail.internet.MimeMessage;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Service;

@Service
public class NotifyService {

    private final JavaMailSender mailSender;

    @Value("${spring.mail.username}")
    private String fromEmail;

    public NotifyService(JavaMailSender mailSender) {
        this.mailSender = mailSender;
    }

    public void sendWelcomeEmail(String to, String fullName) {
        try {
            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");
            helper.setTo(to);
            helper.setFrom(fromEmail, "BrewPOS");
            helper.setSubject("Welcome to BrewPOS!");
            helper.setText(buildHtml(fullName), true); // true = HTML
            mailSender.send(message);
        } catch (Exception e) {
            throw new RuntimeException("Email send failed: " + e.getMessage());
        }
    }

    private String buildHtml(String fullName) {
        return "<!DOCTYPE html>" +
                "<html><head><meta charset='UTF-8'/></head>" +
                "<body style='margin:0;padding:0;background:#0f0a04;font-family:Arial,sans-serif;'>" +
                "<div style='max-width:580px;margin:32px auto;background:#1a1208;" +
                "border-radius:14px;overflow:hidden;'>" +

                // Header
                "<div style='background:#231608;padding:28px 36px;text-align:center;" +
                "border-bottom:1px solid #3d2a10;'>" +
                "<span style='font-size:22px;color:#f5e3c0;font-weight:600;'>" +
                "&#9749; BrewPOS" +
                "</span>" +
                "</div>" +

                // Body
                "<div style='padding:32px 36px;'>" +
                "<p style='font-size:26px;color:#f5e3c0;margin:0 0 10px;'>" +
                "Welcome, " + fullName + "!" +
                "</p>" +
                "<p style='font-size:15px;color:#a8865a;line-height:1.65;margin:0 0 24px;'>" +
                "Your account is ready. Manage orders, inventory," +
                " and reports &#8212; all in one place." +
                "</p>" +
                "<div style='height:1px;background:#3d2a10;margin:0 0 24px;'></div>" +

                // Feature grid (table for email client compatibility)
                "<table width='100%' cellpadding='0' cellspacing='0' " +
                "style='margin-bottom:24px;'>" +
                "<tr>" +
                "<td style='width:50%;padding:0 6px 10px 0;'>" +
                featureBox("Point of Sale", "Fast dine-in &amp; takeout") +
                "</td>" +
                "<td style='width:50%;padding:0 0 10px 6px;'>" +
                featureBox("Inventory", "Real-time stock tracking") +
                "</td>" +
                "</tr>" +
                "<tr>" +
                "<td style='padding:0 6px 0 0;'>" +
                featureBox("Reports", "Daily &amp; monthly insights") +
                "</td>" +
                "<td style='padding:0 0 0 6px;'>" +
                featureBox("Users", "Permissions") +
                "</td>" +
                "</tr>" +
                "</table>" +

                "</div>" +

                // Footer
                "<div style='padding:16px 36px;border-top:1px solid #3d2a10;text-align:center;'>" +
                "<p style='font-size:12px;color:#5a3e18;margin:0;'>" +
                "&#169; 2026 BrewPOS &middot; You received this because you created an account." +
                "</p>" +
                "</div>" +

                "</div>" +
                "</body></html>";
    }


    private String featureBox(String title, String desc) {
        return "<div style='background:#231608;border:1px solid #3d2a10;" +
                "border-radius:9px;padding:14px 16px;'>" +
                "<p style='font-size:13px;font-weight:600;color:#f0d9ae;margin:0 0 4px;'>" +
                title +
                "</p>" +
                "<p style='font-size:12px;color:#7a5a30;margin:0;'>" +
                desc +
                "</p>" +
                "</div>";
    }

    public void sendPasswordResetEmail(String to, String resetLink) {
        try {
            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");
            helper.setTo(to);
            helper.setFrom(fromEmail, "BrewPOS");
            helper.setSubject("Reset Your BrewPOS Password");
            helper.setText(buildResetHtml(resetLink), true);
            mailSender.send(message);
        } catch (Exception e) {
            throw new RuntimeException("Email send failed: " + e.getMessage());
        }
    }

    private String buildResetHtml(String resetLink) {
        return "<!DOCTYPE html>" +
                "<html><head><meta charset='UTF-8'/></head>" +
                "<body style='margin:0;padding:0;background:#0f0a04;font-family:Arial,sans-serif;'>" +
                "<div style='max-width:580px;margin:32px auto;background:#1a1208;border-radius:14px;overflow:hidden;'>" +

                "<div style='background:#231608;padding:28px 36px;text-align:center;border-bottom:1px solid #3d2a10;'>" +
                "<span style='font-size:22px;color:#f5e3c0;font-weight:600;'>&#9749; BrewPOS</span>" +
                "</div>" +

                "<div style='padding:32px 36px;'>" +
                "<p style='font-size:26px;color:#f5e3c0;margin:0 0 10px;'>Password Reset</p>" +
                "<p style='font-size:15px;color:#a8865a;line-height:1.65;margin:0 0 24px;'>" +
                "We received a request to reset your password. " +
                "Click the button below. This link expires in <strong style='color:#f0d9ae;'>1 hour</strong>." +
                "</p>" +
                "<div style='height:1px;background:#3d2a10;margin:0 0 28px;'></div>" +

                "<div style='text-align:center;margin-bottom:28px;'>" +
                "<a href='" + resetLink + "' style='display:inline-block;background:#c47c2b;color:#fff;" +
                "text-decoration:none;font-size:15px;font-weight:600;padding:14px 36px;" +
                "border-radius:8px;'>Reset My Password</a>" +
                "</div>" +

                "<p style='font-size:12px;color:#5a3e18;margin:0 0 4px;'>Or copy this link:</p>" +
                "<p style='font-size:12px;color:#7a5a30;word-break:break-all;margin:0 0 24px;'>" + resetLink + "</p>" +

                "<div style='height:1px;background:#3d2a10;margin:0 0 24px;'></div>" +
                "<p style='font-size:13px;color:#5a3e18;margin:0;'>" +
                "If you didn't request this, you can safely ignore this email." +
                "</p></div>" +

                "<div style='padding:16px 36px;border-top:1px solid #3d2a10;text-align:center;'>" +
                "<p style='font-size:12px;color:#5a3e18;margin:0;'>" +
                "&#169; 2026 BrewPOS &middot; You received this because a reset was requested." +
                "</p></div>" +

                "</div></body></html>";
    }
}