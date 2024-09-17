return [[

integer {
	name = 'flash_addr',
	control = 'select',
	page = 'connection',
	descr = 'firmware flash addr',
	values = {
		0x08000000
	},
	default = 0x08000000,
	format = '0x%08x'
}

number {
	name = 'printer_width',
	descr = 'Print area width',
	default = 200,
	page = 'printer'
}

number {
	name = 'printer_height',
	descr = 'Print area height',
	default = 200,
	page = 'printer'
}

number_list {
	name = 'printer_temperatures',
	descr = 'Print temperatures',
	control = 'list',
	default = {0,100,200},
	default_element = 0,
	page = 'printer'
}

number_list {
	name = 'printer_bed_temperatures',
	descr = 'Print bed temperatures',
	control = 'list',
	default = {0,100},
	default_element = 0,
	page = 'printer'
}

string_list {
	name = 'printer_start_commands',
	descr = 'Printer start commands',
	control = 'list',
	default = {'M119'},
	default_element = 'M119',
	page = 'printer'
}

number {
	name = 'pcb_move_speed',
	descr = 'Idle move speed',
	default = 300,
	page = 'pcb'
}

integer {
	name = 'pcb_outline_count',
	descr = 'Outline count',
	default = 3,
	page = 'pcb'
}

number {
	name = 'pcb_outline_z',
	descr = 'Outline Z',
	default = 100.0,
	page = 'pcb'
}

number {
	name = 'pcb_outline_offset',
	descr = 'Outline offset',
	default = 0.1,
	page = 'pcb'
}

number {
	name = 'pcb_outline_step',
	descr = 'Outline step',
	default = 0.1,
	page = 'pcb'
}

number {
	name = 'pcb_outline_speed',
	descr = 'Outline draw speed',
	default = 300,
	page = 'pcb'
}


number {
	name = 'pcb_fill_z',
	descr = 'Fill Z',
	default = 100.0,
	page = 'pcb'
}

number {
	name = 'pcb_fill_offset',
	descr = 'Fill offset',
	default = 0.1,
	page = 'pcb'
}

number {
	name = 'pcb_fill_step',
	descr = 'Fill step',
	default = 0.1,
	page = 'pcb'
}

number {
	name = 'pcb_fill_offset_x',
	descr = 'Fill offset X',
	default = 0.0,
	page = 'pcb'
}

number {
	name = 'pcb_fill_offset_y',
	descr = 'Fill offset Y',
	default = 0.0,
	page = 'pcb'
}

number {
	name = 'pcb_fill_speed',
	descr = 'Fill draw speed',
	default = 300,
	page = 'pcb'
}

number {
	name = 'pcb_backslash_x',
	descr = 'Backslash compensation X axis',
	default = 0.0,
	page = 'pcb'
}

number {
	name = 'pcb_backslash_y',
	descr = 'Backslash compensation Y axis',
	default = 0.0,
	page = 'pcb'
}]]