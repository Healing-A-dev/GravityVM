const c_setup*: string = """
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <math.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/sendfile.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <time.h>

// --- Memory Tagging Macros ---
#define UNTAG(x) ((x) >> 1)
#define TAG(x) (((x) << 1) | 1)

// Stack Frame & Registers
long long stack[1048576];
long long rsp = 1048575;
long long rbp = 1048575;
double xmm0 = 0.00;
long long sra = 0, srb = 0, src = 0, srd = 0, sre = 0;
long long reg_rdi = 0, reg_rsi = 0, reg_r8 = 0, reg_r9 = 0;
int global_argc;
char** global_argv;

// Predefinition
long long gvm_int_to_str(long long val);

// Runtime Functions
// --- STRINGS ---
long long gvm_str_cat(long long s1, long long s2) {
    char* str1;
    char* str2;

    if (s1 == 0) s1 = (long long)"";
    if (s2 == 0) s2 = (long long)"";

    if (s1 & 1) {
        str1 = (char*)gvm_int_to_str(s1);
    } else {
        str1 = (char*)s1;
    }

    if (s2 & 1) {
        str2 = (char*)gvm_int_to_str(s2);
    } else {
        str2 = (char*)s2;
    }

    char* dest = malloc(strlen(str1) + strlen(str2) + 1);
    strcpy(dest, str1);
    strcat(dest, str2);

    return (long long)dest;
}

// --- FILE I/O ---
// --- Runtime: File I/O --- //
long long gvm_file_open(long long path, long long mode) {
    long long real_mode = UNTAG(mode);
    char* mode_str = "r"; // Always default to read for safety

    if (real_mode == 0) {
        mode_str = "r";   // Read
    } else if (real_mode == 1) {
        mode_str = "w";   // Write (Overwrite)
    } else if (real_mode == 2) {
        mode_str = "a";   // Append
    } else if (real_mode == 3) {
        mode_str = "r+";  // Read/Write
    }

    FILE* f = fopen((char*)path, mode_str);
    return (long long)f;
}

long long gvm_file_read_all(long long path_ptr) {
    FILE *f = fopen((char*)path_ptr, "rb");
    if (f == NULL) return (long long)""; // Return empty string on failure

    // Seek to end to find file size
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET); // Rewind back to start

    // Allocate memory and read
    char *buffer = malloc(fsize + 1);
    fread(buffer, fsize, 1, f);
    fclose(f);

    buffer[fsize] = '\0'; // Null terminate
    return (long long)buffer;
}

void gvm_file_write(long long fd, long long data) {
    fprintf((FILE*)fd, "%s", (char*)data);
}

long long gvm_file_read(long long fd, long long size) {
    char* buffer = malloc(size + 1);
    fread(buffer, 1, size, (FILE*)fd);
    buffer[size] = '\0';
    return (long long)buffer;
}

void gvm_file_close(long long fd) {
    fclose((FILE*)fd);
}

// --- NETWORKING ---
long long gvm_net_socket() {
    return (long long)socket(AF_INET, SOCK_STREAM, 0);
}
void gvm_net_bind(long long fd, long long port) {
    struct sockaddr_in addr;
    addr.sin_family = AF_INET;
    addr.sin_port = htons((int)port);
    addr.sin_addr.s_addr = INADDR_ANY;
    bind((int)fd, (struct sockaddr*)&addr, sizeof(addr));
}
void gvm_net_listen(long long fd) {
    listen((int)fd, 10);
}
long long gvm_net_accept(long long fd) {
    return (long long)accept((int)fd, NULL, NULL);
}
void gvm_net_write(long long fd, long long data) {
    char* str = (char*)data;
    send((int)fd, str, strlen(str), 0);
}

long long gvm_net_recv(long long fd, long long size) {
    char* buffer = malloc(size + 1);
    int bytes = recv((int)fd, buffer, size, 0);
    if (bytes >= 0) {
        buffer[bytes] = '\0';
    } else {
        buffer[0] = '\0'; // Return safe empty string on failure
    }
    return (long long)buffer;
}

void gvm_net_close(long long fd) {
    close((int)fd);
}

// --- NEWTON MAPS ---
// --- NEWTON MAPS & DYNAMIC TYPES ---
typedef struct MapNode {
    long long key;
    long long val;
    struct MapNode* next;
} MapNode;

long long gvm_map_new() {
    // Allocate a container so we can tag the pointer
    MapNode** head = malloc(sizeof(MapNode*));
    *head = NULL;
    return ((long long)head) | 2; // Tag with bit 1 (2) to mark as Map
}

void gvm_map_set(long long map_ptr, long long key, long long val) {
    if (map_ptr == 0) return;
    MapNode** head = (MapNode**)(map_ptr & ~2LL); // Untag pointer
    MapNode* node = malloc(sizeof(MapNode));
    node->key = key; node->val = val; node->next = *head;
    *head = node;
}

long long gvm_map_get(long long map_ptr, long long key) {
    if (map_ptr == 0 || !(map_ptr & 2)) return 0;
    MapNode** head = (MapNode**)(map_ptr & ~2LL);
    MapNode* curr = *head;
    while(curr != NULL) {
        if (curr->key == key) return curr->val;
        curr = curr->next;
    }
    return 0;
}

long long gvm_map_len(long long ptr) {
    if (ptr == 0) return TAG(0); // Null check

    if ((ptr & 2) == 2) {
        // It's a Map! Untag and loop.
        MapNode** head = (MapNode**)(ptr & ~7LL);
        long long count = 0;
        MapNode* curr = *head;
        while(curr != NULL) { count++; curr = curr->next; }
        return TAG(count); // Return a TAGGED integer
    } else if ((ptr & 4) == 4) {
        // It's an Array! Read the dynamic count (index 1 of the metadata block)
        long long* block = (long long*)(ptr & ~7LL);
        return TAG(block[1]);
    } else {
        // It's a String!
        return TAG(strlen((char*)ptr));
    }
}

long long gvm_map_head(long long map_ptr) {
    if (map_ptr == 0 || !(map_ptr & 2)) return 0;
    MapNode** head = (MapNode**)(map_ptr & ~2LL);
    return (long long)*head; // Return raw node (no tag needed for nodes)
}

long long gvm_map_key(long long node_ptr) {
    if (node_ptr == 0) return 0;
    return ((MapNode*)node_ptr)->key;
}

long long gvm_map_val(long long node_ptr) {
    if (node_ptr == 0) return 0;
    return ((MapNode*)node_ptr)->val;
}

long long gvm_map_next(long long node_ptr) {
    if (node_ptr == 0) return 0;
    return (long long)((MapNode*)node_ptr)->next;
}

void gvm_map_del(long long map_ptr, long long key) {
    if (map_ptr == 0 || !(map_ptr & 2)) return;
    MapNode** head = (MapNode**)(map_ptr & ~2LL);
    MapNode* curr = *head;
    MapNode* prev = NULL;

    while (curr != NULL) {
        if (curr->key == key) {
            if (prev == NULL) *head = curr->next;
            else prev->next = curr->next;
            free(curr);
            return;
        }
        prev = curr;
        curr = curr->next;
    }
}

// --- TYPES & CONVERSIONS ---
long long gvm_typeof(long long val) {
    if (val & 1) {
        __attribute__((aligned(8))) static const char int_str[] = "int";
        return (long long)int_str;
    } else if (val & 2) {
        __attribute__((aligned(8))) static const char map_str[] = "map";
        return (long long)map_str;
    } else if (val & 4) {
        __attribute__((aligned(8))) static const char arr_str[] = "list";
        return (long long)arr_str;
    }
    __attribute__((aligned(8))) static const char str_str[] = "string";
    return (long long)str_str;
}

long long gvm_int_to_str(long long val) {
    long long untagged = val >> 1; // Untag the integer
    char* buffer = malloc(32);     // Max 64-bit int length is 20 chars
    sprintf(buffer, "%lld", untagged);
    return (long long)buffer;
}

// --- SYSTEM-ARGS ---
long long gvm_get_argv(long long index) {
    long long idx = index >> 1; // Untag
    if (idx >= 0 && idx < global_argc) {
        return (long long)global_argv[idx];
    }
    return (long long)""; // Return empty string if out of bounds
}
"""

const c_runtime_labels: string = """
    // ==========================================
    // --- NEWTON STANDARD LIBRARY C-RUNTIME ---
    // ==========================================
    // --- Math Runtime ---
    runtime_add:
        sra = TAG(UNTAG(srb) + UNTAG(src));
        goto *(void*)stack[rsp++]; // Only pop return address!

    runtime_sub:
        sra = TAG(UNTAG(srb) - UNTAG(src));
        goto *(void*)stack[rsp++];

runtime_eq:
        // Only use strcmp if BOTH are exactly strings.
        // Integers have bit 1. Maps have bit 2. Arrays have bit 4.
        // Therefore, pure string pointers MUST have none of these bits set: (ptr & 7) == 0.
        if (srb != 0 && src != 0 && (srb & 7) == 0 && (src & 7) == 0) {
            sra = (strcmp((char*)srb, (char*)src) == 0) ? 1 : 0;
        } else {
            sra = (srb == src ? 1 : 0);
        }
        goto *(void*)stack[rsp++];

    runtime_lt:
        sra = (UNTAG(srb) < UNTAG(src) ? 1 : 0); // Removed TAG()
        goto *(void*)stack[rsp++];

    // --- String & IO Runtime ---
    print_string:
        if (srb & 1) {
            printf("%lld", UNTAG(srb));
        } else {
            printf("%s", (char*)srb);
        }
        goto *(void*)stack[rsp++];

    string_concat: {
        char* str1 = (char*)srb;
        char* str2 = (char*)src;
        char* dest = malloc(strlen(str1) + strlen(str2) + 1);
        strcpy(dest, str1);
        strcat(dest, str2);
        sra = (long long)dest;
        goto *(void*)stack[rsp++];
    }

    string_substring: {
        char* str = (char*)srb;
        long long start = UNTAG(src);
        long long len = UNTAG(srd);
        char* dest = malloc(len + 1);
        strncpy(dest, str + start, len);
        dest[len] = '\0';
        sra = (long long)dest;
        goto *(void*)stack[rsp++];
    }

    // Add additional assembly endpoints here!
    exit_program:
        exit(UNTAG(srb));

    sys_log_err:
        // Prints standard errors to the console
        fprintf(stderr, "%s\n", (char*)srb);
        goto *(void*)stack[rsp++];


    // ==========================================
    // --- MISSING SYSTEM & FILE I/O RUNTIME ----
    // ==========================================

    read_file:
        sra = gvm_file_read_all(srb);
        goto *(void*)stack[rsp++];

    sys_access:
        // Checks file permissions/existence (srb = path, src = mode like F_OK)
        // sra = TAG(access((char*)srb, UNTAG(src)));
        sra = TAG(access((char*)srb, 0));
        goto *(void*)stack[rsp++];

    sys_unlink:
        sra = TAG(unlink((char*)srb));
        goto *(void*)stack[rsp++];

    sys_mkdir:
        // Defaults to 0777 permissions
        sra = TAG(mkdir((char*)srb, 0777));
        goto *(void*)stack[rsp++];

    sys_file_size: {
        struct stat st;
        stat((char*)srb, &st);
        sra = TAG(st.st_size);
        goto *(void*)stack[rsp++];
    }

    // ==========================================
    // --- MISSING PROCESS MANAGEMENT RUNTIME ---
    // ==========================================

    sys_fork:
        sra = TAG(fork());
        goto *(void*)stack[rsp++];

    sys_getpid:
        sra = TAG(getpid());
        goto *(void*)stack[rsp++];

    sys_wait: {
        int wstatus;
        sra = TAG(waitpid(UNTAG(srb), &wstatus, 0));
        goto *(void*)stack[rsp++];
    }

    sys_sleep:
        sleep(UNTAG(srb));
        sra = 0;
        goto *(void*)stack[rsp++];

    sys_exec:
        // Executes a shell command (srb = command string)
        sra = TAG(system((char*)srb));
        goto *(void*)stack[rsp++];

    // ==========================================
    // --- MISSING NETWORKING RUNTIME ---
    // ==========================================

    runtime_net_create:
        sra = TAG(socket(AF_INET, SOCK_STREAM, 0));
        goto *(void*)stack[rsp++];

    runtime_net_bind:
        gvm_net_bind(UNTAG(srb), UNTAG(src));
        sra = 0;
        goto *(void*)stack[rsp++];

    runtime_net_listen:
        gvm_net_listen(UNTAG(srb));
        sra = 0;
        goto *(void*)stack[rsp++];

    runtime_net_accept:
        sra = TAG(accept(UNTAG(srb), NULL, NULL));
        goto *(void*)stack[rsp++];

    runtime_net_send:
        send(UNTAG(srb), (char*)src, strlen((char*)src), 0);
        sra = 0;
        goto *(void*)stack[rsp++];

    runtime_net_recv:
        sra = gvm_net_recv(UNTAG(srb), UNTAG(src));
        goto *(void*)stack[rsp++];

    runtime_net_close:
        close(UNTAG(srb));
        sra = 0;
        goto *(void*)stack[rsp++];

    runtime_net_connect: {
        struct sockaddr_in serv_addr;
        serv_addr.sin_family = AF_INET;
        serv_addr.sin_port = htons(UNTAG(src)); // Port
        inet_pton(AF_INET, (char*)srd, &serv_addr.sin_addr); // IP String
        sra = TAG(connect(UNTAG(srb), (struct sockaddr *)&serv_addr, sizeof(serv_addr)));
        goto *(void*)stack[rsp++];
    }

    runtime_net_sendfile: {
        off_t offset = 0;
        // srb = out_fd, src = in_fd, srd = bytes
        sra = TAG(sendfile(UNTAG(srb), UNTAG(src), &offset, UNTAG(srd)));
        goto *(void*)stack[rsp++];
    }

    // ==========================================
    // --- MISSING MATH & LOGIC RUNTIME ---
    // ==========================================

    runtime_or:
        sra = ((srb != 0) || (src != 0)) ? 1 : 0;
        goto *(void*)stack[rsp++];

    runtime_and:
        sra = ((srb != 0) && (src != 0)) ? 1 : 0;
        goto *(void*)stack[rsp++];

    runtime_gt:
        sra = (UNTAG(srb) > UNTAG(src) ? 1 : 0);
        goto *(void*)stack[rsp++];

    runtime_ge:
        sra = (UNTAG(srb) >= UNTAG(src) ? 1 : 0);
        goto *(void*)stack[rsp++];

    runtime_le:
        sra = (UNTAG(srb) <= UNTAG(src) ? 1 : 0);
        goto *(void*)stack[rsp++];

    runtime_mul:
        sra = TAG(UNTAG(srb) * UNTAG(src));
        goto *(void*)stack[rsp++];

    runtime_div:
        // Simple protection against divide-by-zero crashes
        if (UNTAG(src) == 0) { sra = TAG(0); }
        else { sra = TAG(UNTAG(srb) / UNTAG(src)); }
        goto *(void*)stack[rsp++];

    runtime_random:
        // Returns random integer up to UNTAG(srb)
        sra = TAG(rand() % UNTAG(srb));
        goto *(void*)stack[rsp++];

    // ==========================================
    // --- MISSING DATA STRUCTURE RUNTIME ---
    // ==========================================

new_array: {
    long long cap = UNTAG(srb);
    // Allocate block: [Capacity] [Count] [Element 0] [Element 1] ...
    long long* block = (long long*)malloc(sizeof(long long) * (cap + 2));
    block[0] = cap;
    block[1] = 0; // Current count starts at 0
    sra = ((long long)(block)) | 4; // Tag with bit 2 (Value 4) as an Array!
    goto *(void*)stack[rsp++];
}

collection_set: {
    long long* block = (long long*)(srb & ~7LL); // Safely untag the array pointer
    long long index = UNTAG(src);
    long long* elements = block + 2; // Skip metadata
    elements[index] = srd;
    // Automatically grow the length tracker when new items are added!
    if (index >= block[1]) {
        block[1] = index + 1;
    }
    goto *(void*)stack[rsp++];
}

collection_get: {
    long long* block = (long long*)(srb & ~7LL);
    long long index = UNTAG(src);
    long long* elements = block + 2;
    sra = elements[index];
    goto *(void*)stack[rsp++];
}

// ==========================================
// --- MISSING TYPE CASTING RUNTIME ---
// ==========================================
newton_box_float: {
    // Allocate heap space for float to prevent tag collision
    double* box = malloc(sizeof(double));
    *box = *(double*)&srb;
    sra = (long long)box;
    goto *(void*)stack[rsp++];
}

runtime_to_int:
    // Converts a string pointer to a tagged Newton Integer
    sra = TAG(atoll((char*)srb));
    goto *(void*)stack[rsp++];

runtime_to_float: {
    // Converts string to double, then bit-casts to long long representation
    double f_val = atof((char*)srb);
    sra = *(long long*)&f_val;
    goto *(void*)stack[rsp++];
}

runtime_auto_unwrap: {
    long long obj = reg_rdi;
    long long line_num = reg_rsi;

    if (obj & 1) {
        sra = obj;
        goto *(void*)stack[rsp++];
    }

    if ((obj & 7) != 4) {
        sra = obj;
        goto *(void*)stack[rsp++];
    }

    // [0]=capacity, [1]=count, [2]=Index 0, [3]=Index 1
    long long* block = (long long*)(obj & ~7LL);

    if (block[1] < 2) { // Needs at least 2 items to be a valid ["ok", val] Result
        sra = obj;
        goto *(void*)stack[rsp++];
    }
    long long tag_val = block[2]; // Index 0 (The tag)
    long long val_val = block[3]; // Index 1 (The value)

    if (tag_val == 0 || (tag_val & 7) != 0) {
        sra = obj;
        goto *(void*)stack[rsp++];
    }
    char* tag_str = (char*)tag_val;
    if (strcmp(tag_str, "ok") == 0) {
        // SUCCESS: Return the unwrapped value!
        sra = val_val;
        goto *(void*)stack[rsp++];
    }
    else if (strcmp(tag_str, "err") == 0) {
        char* err_msg = (val_val != 0 && (val_val & 7) == 0) ? (char*)val_val : "Unknown Error";

        fprintf(stderr, "\n[FATAL] Auto-Unwrap Error (Line %lld)\n", UNTAG(line_num));
        fprintf(stderr, "└── %s\n\n", err_msg);

        exit(1);
    }
    sra = obj;
    goto *(void*)stack[rsp++];
}

collection_delete: {
    if (reg_rdi == 0) {
        sra = 1; // Return failure
        goto *(void*)stack[rsp++];
    }
    long long* header = (long long*)(reg_rdi & ~7LL);
    long long type_tag = header[-1];
    if (type_tag == 2) {
        gvm_map_del(reg_rdi, reg_rsi);
        sra = 0; // Return success
    }
    else if (type_tag == 4) {
        free(header);
        sra = 0; // Return success
    }
    else {
        sra = 1;
    }
    goto *(void*)stack[rsp++];
}

sys_write_bytes: {
    int fd = (int)(reg_rdi >> 1);
    long long array_obj = reg_rsi;

    if (array_obj == 0 || (array_obj & 7) != 4) {
        sra = 3; // Tagged 1
        goto *(void*)stack[rsp++];
    }

    long long* block = (long long*)(array_obj & ~7LL);
    long long capacity = block[0];
    long long count = block[1];
    long long* elements = block + 2;
    if (count == 0) {
        sra = 3;
        goto *(void*)stack[rsp++];
    }

    char* raw_buffer = (char*)malloc(count);
    for (long long i = 0; i < count; i++) {
        raw_buffer[i] = (char)(elements[i] >> 1);
    }

    write(fd, raw_buffer, count);
    free(raw_buffer);
    sra = 3;
    goto *(void*)stack[rsp++];
}

newton_inc: {
    long long val = reg_rdi;
    if (val == 0) {
        sra = 3;
    } else {
        sra = val + 2;
    }
    goto *(void*)stack[rsp++];
}

runtime_neq: {
    if (srb != 0 && src != 0 && (srb & 7) == 0 && (src & 7) == 0) {
        sra = (strcmp((char*)srb, (char*)src) != 0) ? 1 : 0;
    } else {
        sra = (srb != src) ? 1 : 0;
    }

    goto *(void*)stack[rsp++];
}

collection_get_key: {
    if (reg_rdi == 0) {
        sra = 1; // Return Tagged 0 (failure/null)
        goto *(void*)stack[rsp++];
    }

    long long* header = (long long*)(reg_rdi & ~7LL);
    long long type_tag = header[-1];
    if (type_tag == 2) {
        MapNode* curr = *(MapNode**)(reg_rdi & ~7LL);
        long long index = UNTAG(reg_rsi);
        while (curr != NULL && index > 0) {
            curr = curr->next;
            index--;
        }
        if (curr != NULL) {
            sra = curr->key; // Found
        } else {
            sra = 1; // Tagged 0
        }
    } else {
        sra = reg_rsi;
    }
    goto *(void*)stack[rsp++];
}

newton_sizeof: {
    if (reg_rdi == 0) {
        sra = 1; // Return Tagged 0
        goto *(void*)stack[rsp++];
    }

    long long* header = (long long*)(reg_rdi & ~7LL);
    long long type_tag = header[-1];
    if (type_tag == 1) {
        sra = TAG(strlen((char*)reg_rdi));
    }
    else if (type_tag == 2 || type_tag == 3) {
        sra = gvm_map_len(reg_rdi);
    }
    else if (type_tag == 5) {
        sra = TAG(header[1]);
    }
    else {
        sra = 1; // Default to 0
    }
    goto *(void*)stack[rsp++];
}
"""

const c_comment_char*: string = "//"
const c_entry_start*: string = "int main(int argc, char** argv) {\n    global_argc = argc;\n    global_argv = argv;\n    goto ENTRY;\n"
const c_entry_end*: string = "\n" & c_runtime_labels & "\n}"
const c_entry_call*: string = "main()"
const c_compiler*: string = "gcc"
