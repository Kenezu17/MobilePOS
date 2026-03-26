package com.brewpos.backend.config;

import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseToken;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.stereotype.Component;

import java.io.IOException;

@Component
public class FirebaseAuthFilter implements Filter {

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        HttpServletRequest http = (HttpServletRequest) request;

        if("OPTIONS".equalsIgnoreCase(http.getMethod())){
            chain.doFilter(request,response);
            return;
        }

        String header = http.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
            String token = header.substring(7);
            try {
                FirebaseToken decoded = FirebaseAuth.getInstance().verifyIdToken(token);
                request.setAttribute("uid", decoded.getUid());
                request.setAttribute("email", decoded.getEmail());
            } catch (Exception e) {
                ((HttpServletResponse) response).sendError(401, "Invalid token");
                return;
            }
        }

        chain.doFilter(request, response);
    }
}