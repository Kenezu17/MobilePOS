package com.brewpos.backend.service;

import com.google.cloud.firestore.DocumentSnapshot;
import com.google.cloud.firestore.Firestore;
import com.google.firebase.cloud.FirestoreClient;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.Map;

@Service
public class AdminService {

    private static final String COLLECTION = "admin_users";

    public boolean isAdmin(String uid) throws Exception {
        Firestore db = FirestoreClient.getFirestore();
        DocumentSnapshot doc = db.collection(COLLECTION).document(uid).get().get();
        return doc.exists();
    }

    public void upsertAdmin(String uid, String email) throws Exception {
        Firestore db = FirestoreClient.getFirestore();
        Map<String, Object> data = new HashMap<>();
        data.put("email", email);
        data.put("createdAt", System.currentTimeMillis());
        db.collection(COLLECTION).document(uid).set(data).get();
    }
}