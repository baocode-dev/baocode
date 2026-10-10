// The program the lldb-dap tests debug. The `BP:` markers name lines the
// tests find by text, so lines can move freely.
#include <stdio.h>

static int add(int a, int b) {
  int sum = a + b; // BP:add
  return sum; // BP:add-next
}

static int accumulate(int limit) {
  int total = 0; // BP:accumulate-entry
  for (int i = 0; i < limit; i++) {
    total += i; // BP:loop
  }
  return total; // BP:accumulate-return
}

int main(void) {
  int base = 40;
  int answer = add(base, 2);
  int total = accumulate(5);
  printf("answer=%d total=%d\n", answer, total);
  return 0;
}
