.intel_syntax noprefix
.section .data
    msg: .asciz "Galton Board ASM Simulation Starting...\n"
    msg_done_sim: .asciz "Simulation finished. Rendering...\n"
    done_msg: .asciz "Done in %.3f seconds. Saved to galton_asm.bmp\n"
    msg_no_balls: .asciz "No balls simulated.\n"
    msg_error: .asciz "Error opening file.\n"
    bmp_filename: .asciz "galton_asm.bmp"
    wb_mode: .asciz "wb"

    # Configuration
    width: .quad 1920
    height: .quad 1080
    levels: .quad 100
    num_balls: .quad 1000000

    # Physics Constants
    peg_radius: .double 2.0
    ball_radius: .double 1.5
    peg_spacing_x: .double 18.0
    peg_spacing_y: .double 15.0
    gravity: .double 981.0
    restitution: .double 0.6
    fuzz: .double 10.0
    dt: .double 0.005
    half: .double 0.5
    noise_scale: .double 0.1
    small_eps: .double 0.0001
    two: .double 2.0
    zero: .double 0.0
    one: .double 1.0

    # PRNG state
    prng_state: .quad 123456789

    # Constant floats for gradient
    c_10: .double 10.0
    c_20: .double 20.0
    c_35: .double 35.0
    c_40: .double 40.0
    c_60: .double 60.0
    c_195: .double 195.0
    c_210: .double 210.0
    c_220: .double 220.0

    max_count: .quad 0
    inv_max_h: .double 0.0
    file_ptr: .quad 0

    # BMP Header Template (54 bytes)
    bmp_header:
    .ascii "BM"
    .long 6220854
    .long 0
    .long 54
    .long 40
    .long 1920
    .long 1080
    .word 1 
    .word 24
    .long 0
    .long 6220800
    .long 0
    .long 0
    .long 0
    .long 0

.section .bss
    .lcomm dist, 15360
    .lcomm img_data, 6220800

.section .text
    .global main
    .extern printf, fopen, fwrite, fclose, time

# PRNG
xorshift64star:
    mov rax, [rip + prng_state]
    mov rdx, rax
    shl rdx, 13
    xor rax, rdx
    mov rdx, rax
    shr rdx, 7
    xor rax, rdx
    mov rdx, rax
    shl rdx, 17
    xor rax, rdx
    mov [rip + prng_state], rax
    mov rdx, 0x2545F4914F6CDD1D
    imul rax, rdx
    ret

rand_double:
    sub rsp, 40
    call xorshift64star
    mov rdx, 0x1FFFFFFFFFFFFF
    and rax, rdx
    cvtsi2sd xmm0, rax
    mov rdx, 0x20000000000000
    cvtsi2sd xmm1, rdx
    divsd xmm0, xmm1
    add rsp, 40
    ret

# Ball Simulation
simulate_ball:
    push rbp
    mov rbp, rsp
    sub rsp, 128

    call rand_double
    subsd xmm0, [rip + half]
    mulsd xmm0, [rip + noise_scale]
    cvtsi2sd xmm1, qword ptr [rip + width]
    mulsd xmm1, [rip + half]
    addsd xmm1, xmm0
    movsd [rbp-8], xmm1 # x

    movsd xmm0, [rip + zero]
    movsd [rbp-16], xmm0 # y
    movsd [rbp-24], xmm0 # vx
    movsd [rbp-32], xmm0 # vy

    cvtsi2sd xmm0, qword ptr [rip + levels]
    mulsd xmm0, [rip + peg_spacing_y]
    movsd [rbp-40], xmm0 # max_y

    movsd xmm0, [rip + peg_radius]
    addsd xmm0, [rip + ball_radius]
    mulsd xmm0, xmm0
    movsd [rbp-48], xmm0 # min_dist_sq

sim_loop:
    movsd xmm0, [rbp-16]
    ucomisd xmm0, [rbp-40]
    jnb sim_done

    movsd xmm0, [rbp-8]
    movsd xmm1, [rbp-24]
    mulsd xmm1, [rip + dt]
    addsd xmm0, xmm1
    movsd [rbp-8], xmm0

    movsd xmm0, [rbp-16]
    movsd xmm1, [rbp-32]
    mulsd xmm1, [rip + dt]
    addsd xmm0, xmm1
    movsd xmm2, [rip + gravity]
    mulsd xmm2, [rip + half]
    mulsd xmm2, [rip + dt]
    mulsd xmm2, [rip + dt]
    addsd xmm0, xmm2
    movsd [rbp-16], xmm0

    movsd xmm0, [rbp-32]
    movsd xmm1, [rip + gravity]
    mulsd xmm1, [rip + dt]
    addsd xmm0, xmm1
    movsd [rbp-32], xmm0

    movsd xmm0, [rbp-8]
    ucomisd xmm0, [rip + zero]
    jb left_wall
    cvtsi2sd xmm1, qword ptr [rip + width]
    subsd xmm1, [rip + one]
    ucomisd xmm0, xmm1
    ja right_wall
    jmp peg_collisions

left_wall:
    movsd xmm0, [rip + zero]
    movsd [rbp-8], xmm0
    movsd xmm1, [rbp-24]
    mulsd xmm1, [rip + restitution]
    xorpd xmm2, xmm2
    subsd xmm2, xmm1
    movsd [rbp-24], xmm2
    jmp peg_collisions

right_wall:
    cvtsi2sd xmm1, qword ptr [rip + width]
    subsd xmm1, [rip + one]
    movsd [rbp-8], xmm1
    movsd xmm1, [rbp-24]
    mulsd xmm1, [rip + restitution]
    xorpd xmm2, xmm2
    subsd xmm2, xmm1
    movsd [rbp-24], xmm2

peg_collisions:
    movsd xmm0, [rbp-16]
    divsd xmm0, [rip + peg_spacing_y]
    cvtsd2si r8, xmm0 # row
    cmp r8, 0
    jl sim_loop
    cmp r8, [rip + levels]
    jge sim_loop

    cvtsi2sd xmm0, r8
    mulsd xmm0, [rip + peg_spacing_y]
    movsd [rbp-64], xmm0 # peg_y

    mov rax, r8
    and rax, 1
    jz no_offset
    movsd xmm0, [rip + peg_spacing_x]
    mulsd xmm0, [rip + half]
    movsd [rbp-72], xmm0
    jmp got_offset
no_offset:
    movsd xmm0, [rip + zero]
    movsd [rbp-72], xmm0
got_offset:

    movsd xmm0, [rbp-8]
    subsd xmm0, [rbp-72]
    divsd xmm0, [rip + peg_spacing_x]
    cvtsd2si r10, xmm0 # col
    cvtsi2sd xmm0, r10
    mulsd xmm0, [rip + peg_spacing_x]
    addsd xmm0, [rbp-72] # xmm0 = peg_x

    movsd xmm1, [rbp-8]
    subsd xmm1, xmm0
    movsd xmm2, [rbp-16]
    subsd xmm2, [rbp-64]

    movsd xmm3, xmm1
    mulsd xmm3, xmm3
    movsd xmm4, xmm2
    mulsd xmm4, xmm4
    addsd xmm3, xmm4

    ucomisd xmm3, [rbp-48]
    jnb sim_loop
    ucomisd xmm3, [rip + small_eps]
    jb sim_loop

    sqrtsd xmm4, xmm3
    divsd xmm1, xmm4
    divsd xmm2, xmm4

    movsd xmm5, [rbp-48]
    sqrtsd xmm5, xmm5
    subsd xmm5, xmm4

    movsd xmm0, [rbp-8]
    movsd xmm6, xmm1
    mulsd xmm6, xmm5
    addsd xmm0, xmm6
    movsd [rbp-8], xmm0

    movsd xmm0, [rbp-16]
    movsd xmm6, xmm2
    mulsd xmm6, xmm5
    addsd xmm0, xmm6
    movsd [rbp-16], xmm0

    movsd xmm0, [rbp-24]
    mulsd xmm0, xmm1
    movsd xmm6, [rbp-32]
    mulsd xmm6, xmm2
    addsd xmm0, xmm6 # dot

    ucomisd xmm0, [rip + zero]
    jnb sim_loop

    movsd xmm6, xmm0
    mulsd xmm6, [rip + two]
    movsd xmm5, xmm6 # 2*dot (volatile xmm5)
    mulsd xmm5, xmm1 # 2*dot*nx
    movsd xmm4, [rbp-24]
    subsd xmm4, xmm5
    mulsd xmm4, [rip + restitution]
    movsd [rbp-88], xmm4
    call rand_double
    subsd xmm0, [rip + half]
    mulsd xmm0, [rip + fuzz]
    addsd xmm0, [rbp-88]
    movsd [rbp-24], xmm0

    # vy
    movsd xmm5, xmm6 # 2*dot
    mulsd xmm5, xmm2 # 2*dot*ny
    movsd xmm4, [rbp-32]
    subsd xmm4, xmm5
    mulsd xmm4, [rip + restitution]
    movsd [rbp-88], xmm4
    call rand_double
    subsd xmm0, [rip + half]
    mulsd xmm0, [rip + fuzz]
    addsd xmm0, [rbp-88]
    movsd [rbp-32], xmm0

    jmp sim_loop

sim_done:
    movsd xmm0, [rbp-8]
    cvtsd2si rax, xmm0
    cmp rax, 0
    jge check_upper
    xor rax, rax
    jmp exit_sim
check_upper:
    mov rdx, [rip + width]
    dec rdx
    cmp rax, rdx
    jle exit_sim
    mov rax, rdx
exit_sim:
    leave
    ret

main:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40 # Align stack (8 ops pushed + 40 bytes = 104; entry 8 + 104 = 112 which is 16*7) 
    # Wait: Entry 8 + Push RBP 8 = 16. Correct.
    # Total Pushes: 1+7 = 8. 8*8 = 64. 
    # RSP = 16k + 8 - 64 = 16k - 56.
    # sub rsp, 40 -> RSP = 16k - 96. (96 = 16*6). ALIGNED!

    lea rcx, [rip + msg]
    call printf

    call time
    mov [rip + prng_state], rax

    xor rsi, rsi
ball_main_loop:
    cmp rsi, [rip + num_balls]
    jge simulation_finished
    call simulate_ball
    lea r10, [rip + dist]
    inc qword ptr [r10 + rax*8]
    inc rsi
    jmp ball_main_loop

simulation_finished:
    lea rcx, [rip + msg_done_sim]
    call printf

    xor rax, rax
    xor rdx, rdx
    lea r10, [rip + dist]
find_max:
    cmp rdx, [rip + width]
    jge got_max
    mov r8, [r10 + rdx*8]
    cmp r8, rax
    jle next_max
    mov rax, r8
next_max:
    inc rdx
    jmp find_max

got_max:
    mov [rip + max_count], rax
    cmp rax, 0
    je no_balls_simmed

    cvtsi2sd xmm0, rax
    movsd xmm1, [rip + one]
    divsd xmm1, xmm0
    cvtsi2sd xmm2, qword ptr [rip + height]
    mulsd xmm1, xmm2
    movsd [rip + inv_max_h], xmm1

    xor r12, r12
render_row_loop:
    cmp r12, [rip + height]
    jge rendering_finished
    mov r13, [rip + height]
    sub r13, 1
    sub r13, r12
    cvtsi2sd xmm0, r13
    cvtsi2sd xmm1, qword ptr [rip + height]
    divsd xmm0, xmm1
    ucomisd xmm0, [rip + half]
    ja upper_gradient
    movsd xmm1, xmm0
    addsd xmm1, xmm1
    movsd xmm2, [rip + c_10]
    movsd xmm3, [rip + c_210]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    cvttsd2si r14, xmm2
    movsd xmm2, [rip + c_10]
    movsd xmm3, [rip + c_10]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    cvttsd2si r15, xmm2
    movsd xmm2, [rip + c_40]
    movsd xmm3, [rip + c_20]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    cvttsd2si r11, xmm2
    jmp pixels_loop
upper_gradient:
    movsd xmm1, xmm0
    addsd xmm1, xmm1
    subsd xmm1, [rip + one]
    movsd xmm2, [rip + c_220]
    movsd xmm3, [rip + c_35]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    cvttsd2si r14, xmm2
    movsd xmm2, [rip + c_20]
    movsd xmm3, [rip + c_195]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    cvttsd2si r15, xmm2
    movsd xmm2, [rip + c_60]
    movsd xmm3, [rip + c_60]
    mulsd xmm3, xmm1
    subsd xmm2, xmm3
    cvttsd2si r11, xmm2
pixels_loop:
    xor rsi, rsi
x_loop:
    cmp rsi, [rip + width]
    jge row_done
    mov rax, r12
    imul rax, [rip + width]
    add rax, rsi
    imul rax, 3
    lea r10, [rip + img_data]
    lea rdi, [r10 + rax]
    lea r10, [rip + dist]
    mov rax, [r10 + rsi*8]
    cvtsi2sd xmm0, rax
    mulsd xmm0, [rip + inv_max_h]
    cvttsd2si r8, xmm0
    cmp r13, r8
    jge bg_pixel
    mov [rdi], r11b
    mov [rdi+1], r15b
    mov [rdi+2], r14b
    jmp next_pixel
bg_pixel:
    mov byte ptr [rdi], 15
    mov byte ptr [rdi+1], 10
    mov byte ptr [rdi+2], 10
next_pixel:
    inc rsi
    jmp x_loop
row_done:
    inc r12
    jmp render_row_loop
rendering_finished:
    lea rcx, [rip + bmp_filename]
    lea rdx, [rip + wb_mode]
    call fopen
    mov [rip + file_ptr], rax
    cmp rax, 0
    je render_error
    mov r9, rax
    lea rdx, [rip + bmp_header]
    mov rcx, rdx
    mov rdx, 1
    mov r8, 54
    call fwrite
    mov r12, [rip + height]
    dec r12
write_rows_loop:
    cmp r12, 0
    jl close_file
    mov rax, r12
    imul rax, [rip + width]
    imul rax, 3
    lea r10, [rip + img_data]
    lea rcx, [r10 + rax]
    mov rdx, 1
    mov r8, [rip + width]
    imul r8, 3
    mov r9, [rip + file_ptr]
    call fwrite
    dec r12
    jmp write_rows_loop
close_file:
    mov rcx, [rip + file_ptr]
    call fclose
    lea rcx, [rip + done_msg]
    call printf
    jmp main_exit
no_balls_simmed:
    lea rcx, [rip + msg_no_balls]
    call printf
    jmp main_exit
render_error:
    lea rcx, [rip + msg_error]
    call printf
main_exit:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    xor rax, rax
    ret
