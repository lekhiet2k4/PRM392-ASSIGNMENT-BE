package com.lavela.pool.dto.response;

import com.lavela.pool.domain.enums.UserRole;
import lombok.Builder;
import lombok.Data;

import java.time.LocalDateTime;
import java.util.Set;

@Data
@Builder
public class UserResponse {
    private Long id;
    private String firebaseUid;
    private String fullName;
    private String email;
    private String phone;
    private String status;
    private Set<UserRole> roles;
    private LocalDateTime createdAt;
}
