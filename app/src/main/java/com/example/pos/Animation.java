package com.example.pos;

import android.animation.Animator;
import android.content.Intent;
import android.os.Bundle;

import androidx.appcompat.app.AppCompatActivity;

import com.airbnb.lottie.LottieAnimationView;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseUser;

public class Animation extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.animation);

        LottieAnimationView anim = findViewById(R.id.welcomeAnim);

        anim.setLayerType(android.view.View.LAYER_TYPE_SOFTWARE, null);
        anim.setAnimation(R.raw.welcome);
        anim.setRepeatCount(0);
        anim.playAnimation();

        anim.addAnimatorListener(new android.animation.AnimatorListenerAdapter() {
            @Override
            public void onAnimationEnd(Animator animation) {
                anim.removeAllAnimatorListeners();


                FirebaseUser user = FirebaseAuth.getInstance().getCurrentUser();

                Intent intent;
                if (user != null) {

                    intent = new Intent(Animation.this, MainActivity.class);
                } else {

                    intent = new Intent(Animation.this, Login.class);
                }

                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
                startActivity(intent);
                finish();
            }
        });
    }
}