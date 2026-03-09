package com.lavela.pool.controller;

import com.lavela.pool.dto.request.RegisterRequest;
import com.lavela.pool.dto.response.ApiResponse;
import com.lavela.pool.dto.response.UserResponse;
import com.lavela.pool.security.UserPrincipal;
import com.lavela.pool.service.AuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@Tag(name = "Auth", description = "Firebase authentication")
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;

    /**
     * Register a new user.
     * Flow: Mobile app signs in via Firebase → gets Firebase ID token → sends here.
     * Server verifies token, creates user record with role USER.
     */
    @Operation(summary = "Register with Firebase ID token (public)")
    @PostMapping("/register")
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<UserResponse> register(@Valid @RequestBody RegisterRequest request) {
        return ApiResponse.ok(authService.register(request));
    }

    /**
     * Get profile of the currently authenticated user.
     * Requires valid Firebase ID token in Authorization: Bearer <token>
     */
    @Operation(summary = "Get my profile", security = @SecurityRequirement(name = "bearerAuth"))
    @GetMapping("/me")
    public ApiResponse<UserResponse> me(@AuthenticationPrincipal UserPrincipal principal) {
        return ApiResponse.ok(authService.getProfile(principal.getFirebaseUid()));
    }
}
