			.data
#############
			.align	2
header:		.space	54
pixels:		.space	90000
binary:		.space	4096
#############
			.align	0
err_none:	.asciz	"Finished\n"
err_prog:	.asciz	"Invalid program\n"
err_rbmp:	.asciz	"Error reading template bitmap\n"
err_rbin:	.asciz	"Error reading program binary\n"
err_wbmp:	.asciz	"Error writing result bitmap\n"
dbg_pos:	.asciz	"Position: "
dbg_dir:	.asciz	"Direction: "
dbg_pen:	.asciz	"Brush: "
dbg_mov:	.asciz	"Move: "

path_rbmp:	.asciz	"template.bmp"
path_wbmp:	.asciz	"result.bmp"
path_rbin:	.asciz	"turtle_test1_v6.bin"

#############
			.align	2
			.eqv	ERR_NONE 		0
			.eqv	ERR_READ_BMP 	1
			.eqv	ERR_READ_BIN 	2
			.eqv	ERR_PROG_SIZE	3
			.eqv	ERR_WRITE_BMP	4
errors:		.word	err_none, err_rbmp, err_rbin, err_prog, err_wbmp
opcodes:	.word	op_move, op_pen, op_position, op_direction
directions:	.word	move_up, move_lt, move_dn, move_rt
brush_mode:	.word	brush_draw, brush_skip
brushes:	.word	0x000000, 0xFF00FF, 0xFFFF00, 0x00FFFF, 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFFFF
#############
			.text
### macros ###
.macro	fopen(%path, %mode, %err)
	la		a0, %path
	li		a1, %mode
	li		a7, 1024
	ecall
	bltz	a0, %err
.end_macro
.macro 	fread(%file, %into, %size, %err)
	mv		a0, %file
	la		a1, %into
	li		a2, %size
	li		a7, 63
	ecall
	bltz	a0, %err
.end_macro
.macro 	fwrite(%file, %from, %size, %err)
	mv		a0, %file
	la		a1, %from
	li		a2, %size
	li		a7, 64
	ecall
	bne		a0, a2, %err
.end_macro
.macro	fclose(%file)
	mv		a0, %file
	li		a7, 57
	ecall
.end_macro
.macro	read_vtable(%into, %vtable, %index)
	la		t0, %vtable
	slli	t1, %index, 2
	add		t0, t0, t1
	lw		%into, (t0)
.end_macro
.macro	putc(%char)
	li		a0, %char
	li		a7, 11
	ecall
.end_macro
.macro	putreg(%reg)
	mv		a0, %reg
	li		a7, 34
	ecall
.end_macro

### variables ###
.eqv	hFile	s0
.eqv	eCode	s1
.eqv	fSize	s2
main:
	## try opening template file
	fopen(path_rbmp, 0, handle_error_rbmp)
	## preserve descriptor
	mv		hFile, a0
	## try reading
	fread(hFile, header, 54, handle_error_rbmp)
	fread(hFile, pixels, 90000, handle_error_rbmp)
	## close descriptor
	fclose(hFile)
	
	## try opening program file
	fopen(path_rbin, 0, handle_error_rbin)
	## preserve descriptor
	mv		hFile, a0
	## try reading
	fread(hFile, binary, 4096, handle_error_rbin)
	mv		fSize, a0
	## close descriptor
	fclose(hFile)
	
	## call turtle function
	la		a0, pixels
	la		a1, binary
	mv		a2, fSize
	call	turtle
	
	## try opening result file
	fopen(path_wbmp, 1, handle_error_wbmp)
	## preserve descriptor
	mv		hFile, a0
	## try writing
	fwrite(hFile, header, 54, handle_error_wbmp)
	fwrite(hFile, pixels, 90000, handle_error_wbmp)
	## close descriptor
	fclose(hFile)
	
handle_error:
	## print the appropriate exit message / error
	read_vtable(a0, errors, eCode)
	li		a7, 4
	ecall
	
	## exit properly
	li		a7, 10
	ecall
			
			
### arguments ###
.eqv    dest_bitmap     s0
.eqv    program 		s1
.eqv    program_size    s2
### variables ###
.eqv    turtle_x        s3
.eqv    turtle_y        s4
.eqv    turtle_d        s5
.eqv    turtle_m        s6
.eqv    brush_ud        s7
.eqv    brush_ci        s8
.eqv    instruction     s9
.eqv	dest_pixel		s10
.eqv	last_error		s11
### macros ###
.macro	read_instruction(%eq, %gt)
	beq		program, program_size, %eq
	bgt		program, program_size, %gt
	lbu		t0, 1(program)
	lbu		t1, 0(program)
	slli	t1, t1, 8
	or		instruction, t0, t1
	addi	program, program, 2
.end_macro
.macro	read_field(%into, %shamt, %mask)
	srli	t0, instruction, %shamt
	andi	%into, t0, %mask
.end_macro
.macro	try_step(%coord, %step, %limit, %wall)
	li		t0, %limit
	beq		%coord, t0, %wall
	addi	%coord, %coord, %step
.end_macro
### implementation
turtle:
	## Preserve registers
	addi    sp, sp, -0x2C
	sw      s0, 0x00(sp)
	sw      s1, 0x04(sp)
	sw      s2, 0x08(sp)
	sw      s3, 0x0C(sp)
	sw      s4, 0x10(sp)
	sw      s5, 0x14(sp)
	sw      s6, 0x18(sp)
	sw      s7, 0x1C(sp)
	sw      s8, 0x20(sp)
	sw      s9, 0x24(sp)
	sw      s10, 0x28(sp)
	## initialize
	mv		dest_bitmap, a0
	mv		program, a1
	add		a2, a2, a1
	mv		program_size, a2
	mv		turtle_x, zero
	mv		turtle_y, zero
	mv		turtle_m, zero
	la		turtle_d, directions
	lw		turtle_d, (turtle_d)
	la		brush_ud, brush_mode
	lw		brush_ud, (brush_ud)
	mv		dest_pixel, dest_bitmap
	## instructions
turtle_logic:
	read_instruction(turtle_finish, handle_error_program)
	read_field(t6, 14, 0x3)
	read_vtable(t0, opcodes, t6)
	jr		t0
	## set position instruction
op_position:
	read_field(turtle_y, 8, 0x3F)
	read_instruction(handle_error_program, handle_error_program)
	read_field(turtle_x, 6, 0x3FF)
	b		turtle_logic
	## set direction instruction
op_direction:
	read_field(turtle_d, 10, 0x3)
	read_vtable(turtle_d, directions, turtle_d)
	b		turtle_logic
	## move instruction
op_move:
	read_field(turtle_m, 4, 0x3FF)
move_step:
	blez	turtle_m, turtle_logic
	jr		brush_ud
brush_draw:
	## compute destination pixel offset
	li		t0, 3
	mul		t0, t0, turtle_x
	li		t1, 1800
	mul		t1, t1, turtle_y
	add		t0, t0, t1
	add		dest_pixel, t0, dest_bitmap
	## write color channels to destination pixel
	mv		t0, brush_ci
	sb		t0, 2(dest_pixel)
	srli	t0, t0, 8
	sb		t0, 1(dest_pixel)
	srli	t0, t0, 8
	sb		t0, 0(dest_pixel)	
brush_skip:
	addi	turtle_m, turtle_m, -1
	jr		turtle_d
move_up:
	try_step(turtle_y, 1, 50, turtle_logic)
	b		move_step
move_dn:
	try_step(turtle_y, -1, 0, turtle_logic)
	b		move_step
move_lt:
	try_step(turtle_x, -1, 0, turtle_logic)
	b		move_step
move_rt:
	try_step(turtle_x, +1, 600, turtle_logic)
	b		move_step
	## set pen state instruction
op_pen:
	read_field(brush_ud, 12, 0x1)
	read_field(brush_ci, 8, 0x7)
	read_vtable(brush_ud, brush_mode, brush_ud)
	read_vtable(brush_ci, brushes, brush_ci)
	b		turtle_logic
turtle_finish:
	## last_error = ERR_NONE
	li		last_error, ERR_NONE
	## return label
turtle_return:
	## return last_error
	mv		a0, last_error
	## Restore preserved registers
	lw      s0, 0x00(sp)
	lw      s1, 0x04(sp)
	lw      s2, 0x08(sp)
	lw      s3, 0x0C(sp)
	lw      s4, 0x10(sp)
	lw      s5, 0x14(sp)
	lw      s6, 0x18(sp)
	lw      s7, 0x1C(sp)
	lw      s8, 0x20(sp)
	lw      s9, 0x24(sp)
	lw      s10, 0x28(sp)
	addi    sp, sp, +0x2C
	## jr	ra
	ret
	
## error handling
handle_error_program:
	li		last_error, ERR_PROG_SIZE
	b		turtle_return
handle_error_rbmp:
	li		eCode, ERR_READ_BMP
	b		handle_error
handle_error_rbin:
	li		eCode, ERR_READ_BIN
	b		handle_error
handle_error_wbmp:
	li		eCode, ERR_WRITE_BMP
	b		handle_error