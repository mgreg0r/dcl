SYS_WRITE equ 1
SYS_EXIT equ 60
STDOUT equ 1
PSIZE equ 42
BUFSIZE equ 4096

global _start

section .data
linv: times PSIZE db 0                    ; inverted L permutation
rinv: times PSIZE db 0                    ; inverted R permutation
tinv: times PSIZE db 0                    ; inverted T position

section .bss
buffer resb BUFSIZE                       ; input buffer
rd_len resq 1                             ; input length
lpos: resb 1
rpos: resb 1


; Implements the write system call
%macro write_string 2
    mov               rax, 1
    mov               rdi, 1
    mov               rsi, %1
    mov               rdx, %2
    syscall           
%endmacro

; Wrapper for frotate function, handles argument passing
%macro rotate 2
    mov               al, %1
    mov               bl, %2
    call              frotate
    mov               %1, al
%endmacro

; translates character in al, using input permutation stored in [rsp + %1]
%macro permutate 1
    lea               rbp, [rsp + %1]
    mov               rdx, [rbp]
    mov               al, [rdx+rcx]
    sub               al, 0x31
    mov               cl, al
%endmacro

; translates character in al, using inverted permutation stored in %1
%macro permutate_inv 1
    mov               rdx, %1
    mov               al, [rdx+rcx]
    mov               cl, al
%endmacro

; wrapper for calc_inversion function, handles argument passing
%macro invert_perm 2
    lea               rbp, [rsp + %1]
    mov               rsi, [rbp]
    validate_length   rsi, 43
    mov               rcx, %2
    call              calc_inversion
%endmacro

; jumps to error handling if length of %1 is not %2
%macro validate_length 2
    xor               al, al
    mov               ecx, %2
    inc               ecx
    mov               rdi, %1
repne \
    scasb             
    sub               rdi, rsi
    cmp               rdi, %2
    jne               error
%endmacro

; jumps to error handling if %1 is out of range [1-Z]
%macro validate_char 1
    cmp               %1, 0x31
    jl                error
    cmp               %1, 0x5a
    jg                error
%endmacro

section .text

; inverts permutation stored in rsi, and saves it in memory pointed by rcx
calc_inversion:
    xor               rax, rax
    xor               rbx, rbx            ; iterating through [0..41]
prepare_inv:
    mov               al, [rsi + rbx]     ; saving next character in al
    validate_char     al
    sub               al, 0x31            ; calculating offset from character '1'
    cmp               BYTE [rcx + rax], 0 ; check if this position is not already taken
    jne               error
    mov               [rcx + rax], bl     ; saving current iteration number in correct result position
    inc               rbx
    cmp               rbx, 42             ; ending loop after reaching last character
    jl                prepare_inv
    ret               

; rotates character stored in al by number stored in bl
frotate:
    cmp               al, 41              ; fixing initial overflow
    jle               actrotate
    sub               al, 42
actrotate:
    add               al, bl
fixoverflow:                              ; fixing overflow (al + bl > 41)
    cmp               al, 41
    jle               ret_rotate
    sub               al, 42
    jmp               fixoverflow
    ret_rotate:       
    ret               

; rotates character stored in cl, by inverted L position
    inv_rotate_left:  
    cmp               BYTE [lpos], 0      ; if L = 0, we're not rotating
    jg                lqop
    rotate            cl, 0
    jmp               lpostqop
lqop:
    mov               dl, 42              ; calculating inversion (42 - [lpos])
    sub               dl, [lpos]
    rotate            cl, dl
lpostqop:
    ret               

; rotates character stored in cl, by inverted R position
    inv_rotate_right: 
    cmp               BYTE [rpos], 0      ; if R = 0, we're not rotating
    jg                rqop
    rotate            cl, 0
    jmp               rpostqop
rqop:
    mov               dl, 42              ; calculating inversion (42 - [rpos])
    sub               dl, [rpos]
    rotate            cl, dl
rpostqop:
    ret               

_start:
    lea               rbp, [rsp + 40]     ; getting last program parameter
    mov               rsi, [rbp]
    validate_length   rsi, 3
    mov               al, [rsi]           ; getting first character (initial L position)
    validate_char     al
    sub               al, 0x31
    mov               [lpos], al          ; storing it in lpos
    mov               al, [rsi + 1]       ; getting second character (initial R position)
    validate_char     al
    sub               al, 0x31
    mov               [rpos], al          ; storing it in rpos

    invert_perm       16, linv            ; inverting L permutation, and saving it in linv
    invert_perm       24, rinv            ; inverting R permutation, and saving it in rinv
    invert_perm       32, tinv            ; inverting T permutation, for verification purposes

read_input:
    xor               rdi, rdi
    xor               eax, eax            ; reading input
    xor               ebx, ebx
    mov               rsi, buffer
    mov               edx, BUFSIZE
    syscall           
    mov               [rd_len], eax       ; storing input length

    xor               rcx, rcx
    xor               rdi, rdi
procch:
    cmp               edi, DWORD [rd_len] ; finish calculations after reaching end of text
    je                postproc
    mov               cl, BYTE [rsi]
    validate_char     cl
    sub               cl, 0x31            ; calculating offset from symbol '1'

    rotate            [rpos], 1           ; rotating R by 1 position
    cmp               BYTE [rpos], 27
    je                rot_left
    cmp               BYTE [rpos], 33
    je                rot_left
    cmp               BYTE [rpos], 35
    je                rot_left
    jmp               perm

rot_left:
    rotate            [lpos], 1           ; rotating L by 1 position only if needed

perm:                                     ; translating current character through all needed permutations
    rotate            cl, BYTE [rpos]
    permutate         24
    call              inv_rotate_right
    rotate            cl, BYTE [lpos]
    permutate         16
    call              inv_rotate_left
    permutate         32
    rotate            cl, BYTE [lpos]
    permutate_inv     linv
    call              inv_rotate_left
    rotate            cl, BYTE [rpos]
    permutate_inv     rinv
    call              inv_rotate_right

    add               cl, 0x31
    mov               BYTE [rsi], cl      ; saving result
    inc               rsi
    inc               edi
    jmp               procch

postproc:                                 ; all characters in buffer have been translated
    write_string      buffer, [rd_len]
    cmp               WORD [rd_len], 4096
    jge               read_input


exit:
    mov               eax, SYS_EXIT
    xor               edi, edi
    syscall           

error:
    mov               eax, SYS_EXIT
    mov               edi, 1
    syscall           
