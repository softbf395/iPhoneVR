#ifndef ALVR_CLIENT_CORE_H
    #define ALVR_CLIENT_CORE_H

    #include <stdint.h>
    #include <stdbool.h>

    // Basic Types for ALVR
    typedef struct {
        float orientation[4]; // x, y, z, w
        float position[3];    // x, y, z
    } AlvrPose;

    typedef struct {
        uint64_t target_timestamp_ns;
        AlvrPose device_motions[3]; // Head, Left Hand, Right Hand
        float left_hand_skeleton[26][7]; 
        float right_hand_skeleton[26][7];
    } AlvrTracking;

    // Functions
    void alvr_initialize(const char *user_config_dir, const char *base_config_dir, int log_level);
    void alvr_destroy(void);
    void alvr_resume(void);
    void alvr_pause(void);
    void alvr_send_tracking(AlvrTracking tracking);
    uint64_t alvr_get_protocol_id(void);
    
    // Log levels
    #define ALVR_LOG_LEVEL_INFO 0
    #define ALVR_LOG_LEVEL_WARN 1
    #define ALVR_LOG_LEVEL_ERROR 2

    #endif
