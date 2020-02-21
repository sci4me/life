package playground

import "core:fmt"
import "core:mem"
import "core:math"
import "core:math/rand"
import "core:strings"
import bs "shared:odin-sparse_bitset"

import glfw "shared:odin-glfw/bindings"
import gl "shared:odin-gl"

WIDTH :: 1280;
HEIGHT :: 720;

GL_MAJOR :: 4;
GL_MINOR :: 4;

Pixel :: struct {
	a: u8,
	r: u8,
	g: u8,
	b: u8
}

RED := Pixel{0xFF, 0x00, 0x00, 0xFF};
BLACK := Pixel{0x00, 0x00, 0x00, 0xFF};

scale :: proc(x: f64, in_min: f64, in_max: f64, out_min: f64, out_max: f64) -> f64 {
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}

fill_rect :: proc(pixels: []Pixel, x: int, y: int, w: int, h: int, color: Pixel) {
    x2 := x + w;
    y2 := y + h;
    for y in y..<y2 {
        for x in x..<x2 {
            pixels[x + y * WIDTH] = color;
        }
    }
}

CELL_SIZE :: 5;
GRID_WIDTH :: WIDTH / CELL_SIZE;
GRID_HEIGHT :: HEIGHT / CELL_SIZE;
GRID_COUNT :: GRID_WIDTH * GRID_HEIGHT / 8;
 
grid_a : ^[GRID_COUNT]u8;
grid_b : ^[GRID_COUNT]u8;

init :: proc() {
    grid_a = new([GRID_COUNT]u8);
    grid_b = new([GRID_COUNT]u8);

    for i in 0..<GRID_COUNT/size_of(u64) {
        x := rand.uint64();
        inline for j in 0..<8 {
            grid_a[i * size_of(u64) + j] = u8((x >> (uint(i) << 3)) & 0xFF);
        }
    }
}

elem :: inline proc(i: int) -> (int, int) {
    return i / 8, i % 8;
}

get :: inline proc(grid: ^[GRID_COUNT]u8, x, y: int) -> bool {
    i, j := elem(x + y * GRID_WIDTH);
    return grid[i] & (1 << uint(j)) != 0;
}

set :: inline proc(grid: ^[GRID_COUNT]u8, x, y: int, value: bool) {
    i, j := elem(x + y * GRID_WIDTH);
    if value do grid[i] |= (1 << uint(j));
    else do grid[i] &= ~(1 << uint(j));
}

count_neighbors :: proc(grid: ^[GRID_COUNT]u8, x, y: int) -> int {
    n := 0;

    for j in -1..1 {
        for i in -1..1 {
            if i == 0 && j == 0 do continue;

            k := x + i;
            l := y + j;

            if k < 0 do k += GRID_WIDTH;
            if l < 0 do l += GRID_HEIGHT;
            if k >= GRID_WIDTH do k -= GRID_WIDTH;
            if l >= GRID_HEIGHT do l -= GRID_HEIGHT;

            if get(grid, k, l) do n += 1;
        }
    }

    return n;
}

tick :: proc() {
    grid_a_ := transmute(^[GRID_COUNT/4]u32)grid_a;
    grid_b_ := transmute(^[GRID_COUNT/4]u32)grid_b;

    for i in 0..<GRID_COUNT/4 {
        k := i * 4;

        cells := grid_a_[i];
        eq_2s, eq_3s : u32;

        inline for l in 0..<4 {
            eq_2, eq_3 : u8;

            inline for j in 0..<8 {
                x := (((k + l) * 8) + j) % GRID_WIDTH;
                y := (((k + l) * 8) + j) / GRID_WIDTH;

                n := count_neighbors(grid_a, x, y);

                if n == 2 do eq_2 |= (1 << uint(j));
                if n == 3 do eq_3 |= (1 << uint(j));
            }

            shift := uint(l << 3);
            mask := u32(0xFF << shift);
            eq_2s = (eq_2s & ~mask) | (u32(eq_2) << shift);
            eq_3s = (eq_3s & ~mask) | (u32(eq_3) << shift);
        }

        grid_b_[i] = (eq_2s & cells) | eq_3s;
    }

    tmp := grid_a;
    grid_a = grid_b;
    grid_b = tmp;
}

render :: proc(pixels: []Pixel) {
    for i in 0..<GRID_COUNT {
        j := i * 8;

        x := j % GRID_WIDTH;
        y := j / GRID_WIDTH;

        cell := grid_a[i];

        for k in 0..<8 {
            color := BLACK;
            if grid_a[i] & (1 << uint(k)) != 0 do color = RED;

            fill_rect(pixels, (x + k) * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE, color);
        }
    }
}

get_uniform_location :: proc(program: u32, str: string) -> i32 {
    return gl.GetUniformLocation(program, strings.unsafe_string_to_cstring(str));
}

error_callback :: proc "c" (error: i32, desc: cstring) {
    fmt.printf("Error code %d:\n    %s\n", error, desc);
}

main :: proc() {
    glfw.SetErrorCallback(error_callback);

    if glfw.Init() == 0 do return;
    defer glfw.Terminate();

    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR);
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR);
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE);
    glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE);

    window := glfw.CreateWindow(WIDTH, HEIGHT, "Conway's Game of Life", nil, nil);
    if window == nil do panic("Failed to create window!");

    glfw.MakeContextCurrent(window);
    glfw.SwapInterval(0);

    set_proc_address :: proc(p: rawptr, name: cstring) { 
        (cast(^rawptr)p)^ = rawptr(glfw.GetProcAddress(name));
    }
    gl.load_up_to(GL_MAJOR, GL_MINOR, set_proc_address);

    program, shader_success := gl.load_shaders("shaders/shader_passthrough.vs", "shaders/shader_passthrough.fs");
    if !shader_success do panic("Failed to load shaders!");
    defer gl.DeleteProgram(program);

    gl.UseProgram(program);
    gl.Uniform2f(get_uniform_location(program, "tex_size\x00"), WIDTH, HEIGHT);

    vao: u32;
    gl.GenVertexArrays(1, &vao);
    defer gl.DeleteVertexArrays(1, &vao);

    gl.BindVertexArray(vao);

    vertex_data := [?]f32{
        -1.0,  1.0,
        -1.0, -1.0, 
         1.0,  1.0, 
         1.0, -1.0
    };

    vbo: u32;
    gl.GenBuffers(1, &vbo);
    defer gl.DeleteBuffers(1, &vbo);

    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.BufferData(gl.ARRAY_BUFFER, size_of(vertex_data), &vertex_data[0], gl.STATIC_DRAW);

    gl.EnableVertexAttribArray(0);
    gl.VertexAttribFormat(0, 2, gl.FLOAT, gl.FALSE, 0);
    gl.VertexAttribBinding(0, 0);
    gl.BindVertexBuffer(0, vbo, 0, 8);

    tex: u32;
    gl.GenTextures(1, &tex);
    defer gl.DeleteTextures(1, &tex);

    gl.ActiveTexture(gl.TEXTURE0);
    gl.BindTexture(gl.TEXTURE_2D, tex);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

    pbos : [2]u32;
    gl.GenBuffers(2, &pbos[0]);
    defer gl.DeleteBuffers(2, &pbos[0]);
    
    frames := 0;
    ticks := 0;

    index := 0;
    next_index : type_of(index);

    init();

    timer := glfw.GetTime();

    for glfw.WindowShouldClose(window) == glfw.FALSE {
        glfw.PollEvents();

        {
            index = (index + 1) % 2;
            next_index = (index + 1) % 2;

            gl.BindTexture(gl.TEXTURE_2D, tex);

            gl.BindBuffer(gl.PIXEL_UNPACK_BUFFER, pbos[index]);
            gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, WIDTH, HEIGHT, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil);

            gl.BindBuffer(gl.PIXEL_UNPACK_BUFFER, pbos[next_index]);
            gl.BufferData(gl.PIXEL_UNPACK_BUFFER, WIDTH*HEIGHT*4, nil, gl.STREAM_DRAW);

            ptr := gl.MapBuffer(gl.PIXEL_UNPACK_BUFFER, gl.WRITE_ONLY);
            if ptr != nil {
                pixels := mem.slice_ptr(cast(^Pixel)ptr, size_of(Pixel) * WIDTH * HEIGHT);
        
                tick();
                render(pixels);
        
                frames += 1;

                gl.UnmapBuffer(gl.PIXEL_UNPACK_BUFFER);
            }
            
            gl.BindBuffer(gl.PIXEL_UNPACK_BUFFER, 0);
        }        

        gl.BindVertexArray(vao);
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4);
        
        glfw.SwapBuffers(window);

        if glfw.GetTime() - timer >= 1 {
            fmt.println("FPS:", frames);

            timer += 1;
            frames = 0;
            ticks = 0;
        }
    }
}