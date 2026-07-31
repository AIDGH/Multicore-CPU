ACQUIRE_LOCK:
    lr.w    R2, (R1)
    bne     R2, R0, ACQUIRE_LOCK

    addi    R3, R0, 1
    sc.w    R3, (R1)
    bne     R3, R0, ACQUIRE_LOCK

CRITICAL_SECTION:
    lw      R4, (R5)
    addi    R4, R4, 1
    sw      R4, (R5)

RELEASE_LOCK:
    sw      R0, (R1)