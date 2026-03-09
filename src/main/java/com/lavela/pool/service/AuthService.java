package com.lavela.pool.service;

import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseToken;
import com.lavela.pool.domain.entity.User;
import com.lavela.pool.domain.enums.UserRole;
import com.lavela.pool.dto.request.RegisterRequest;
import com.lavela.pool.dto.response.UserResponse;
import com.lavela.pool.exception.AuthException;
import com.lavela.pool.exception.ResourceNotFoundException;
import com.lavela.pool.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Set;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final UserRepository userRepository;

    @Transactional
    public UserResponse register(RegisterRequest request) {
        // Verify Firebase ID token
        FirebaseToken firebaseToken;
        try {
            firebaseToken = FirebaseAuth.getInstance().verifyIdToken(request.getFirebaseIdToken());
        } catch (Exception e) {
            throw new AuthException("Invalid Firebase token: " + e.getMessage());
        }

        String firebaseUid = firebaseToken.getUid();
        // Use email from token if available, fallback to request body
        String email = firebaseToken.getEmail() != null ? firebaseToken.getEmail() : request.getEmail();

        if (userRepository.existsByFirebaseUid(firebaseUid)) {
            throw new AuthException("User already registered");
        }
        if (userRepository.existsByEmail(email)) {
            throw new AuthException("Email already in use");
        }

        User user = User.builder()
                .firebaseUid(firebaseUid)
                .fullName(request.getFullName())
                .email(email)
                .phone(request.getPhone())
                .roles(Set.of(UserRole.USER))
                .build();

        return toResponse(userRepository.save(user));
    }

    @Transactional(readOnly = true)
    public UserResponse getProfile(String firebaseUid) {
        User user = userRepository.findByFirebaseUid(firebaseUid)
                .orElseThrow(() -> new ResourceNotFoundException("User not found"));
        return toResponse(user);
    }

    private UserResponse toResponse(User user) {
        return UserResponse.builder()
                .id(user.getId())
                .firebaseUid(user.getFirebaseUid())
                .fullName(user.getFullName())
                .email(user.getEmail())
                .phone(user.getPhone())
                .status(user.getStatus())
                .roles(user.getRoles())
                .createdAt(user.getCreatedAt())
                .build();
    }
}
