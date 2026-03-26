package com.brewpos.backend;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HomeController {

    @GetMapping("/")
    public String home() {
        return "brewpos-backend is running ";
    }

    @GetMapping("/health")
    public String health() {
        return "OK";
    }
}
