
// NOTE(tt): linked lists

LinkedListAdd
:: (First: **$T, Value: *T, $NextName := "Next")
{
  #insert #run tprint("Next := *Value.%;", NextName);
  Next.* = First.*;
  First.* = Value;
}

linked_list
:: struct($T: Type)
{
  First: *T;
  NextName: string;
}

EachElement
:: (First: *$T, $NextName := "Next")
-> linked_list
{
  return .{First, NextName};
}

for_expansion
:: (List: linked_list($T), Body: Code, Flags: For_Flags) #expand
{
  Value := List.First;
  Index := 0;

  while Value
  {
    `it := Value;
    `it_index := Index;

    {
      #insert Body;
    }

    #insert #run tprint("Value := Value.%;", List.NextName);
    Index += 1;
  }
}

// NOTE(tt): math stuff

vec2i
:: struct
{
  x, y: int;
}

vec2 :: Vector2;
vec3 :: Vector3;
vec4 :: Vector4;
Max :: max;
Min :: min;
Abs :: abs;
ModFloat :: fmod_cycling;
Lerp :: lerp;
Distance :: distance;
Clamp :: clamp;

Remap
:: (X: float, MinA: float, MaxA: float, MinB: float, MaxB: float)
-> float
{
  return MinB + (X - MinA) * (MaxB - MinB) / (MaxA - MinA);
}

quad
:: struct
{
  Left, Top, Right, Bottom: float;
}

// NOTE(tt): hashing

HashString :: get_hash;

// NOTE(tt): misc

QuickSort :: quick_sort;

// NOTE(tt): memory stuff

Zero
:: (Memory: *void, Size: int)
{
  memset(Memory, 0, Size);
}

Copy
:: (Dest: *void, Source: *void, Size: int)
{
  memcpy(Dest, Source, Size);
}

// NOTE(tt): arenas

arena_default_reserve :: 1024*1024*1024*4;
arena_default_commit :: 1024*16;

arena
:: struct
{
  Base: *u8;
  Reserved: int;
  Committed: int;
  Used: int;
  Mark: int;
}

CreateArena
:: ()
-> *arena
{
  Base := PlatformReserve(arena_default_reserve);
  PageSize := PlatformPageSize();
  Commit := (arena_default_commit + size_of(arena) + PageSize - 1) & (~PageSize - 1);
  PlatformCommit(Base, Commit);
  Arena := cast(*arena) Base;
  Arena.Base = Base + size_of(arena);
  Arena.Reserved = arena_default_reserve;
  Arena.Committed = Commit;
  Zero(Arena.Base, Arena.Committed);
  return Arena;
}

ArenaAlloc
:: (Arena: *arena, Size: int, $L := #caller_location)
-> *void
{
  if Arena.Used + Size >= Arena.Committed
  {
    PageSize := PlatformPageSize();
    AlignedSize := (Size + PageSize - 1) & ~(PageSize - 1);
    Commit := max(arena_default_commit, AlignedSize);
    PlatformCommit(Arena.Base + Arena.Committed, Commit);
    Arena.Committed += Commit;
  }
  Memory := Arena.Base + Arena.Used;
  Arena.Used += Size;
  Zero(Memory, Size);
  return Memory;
}

ArenaPushStruct
:: (Arena: *arena, $T: Type, Count := 1, $L := #caller_location)
-> *T
{
  Result := ArenaAlloc(Arena, size_of(T) * Count, L);
  return Result;
}

ArenaPushView
:: (Arena: *arena, $T: Type, Count: int, $L := #caller_location)
-> [] T
{
  return .{Count, ArenaPushStruct(Arena, T, Count, L)};
}

ArenaPushString
:: (Arena: *arena, String: string, $L := #caller_location)
-> string
{
  Data := ArenaAlloc(Arena, String.count, L);
  Copy(Data, String.data, String.count);
  return .{String.count, Data};
}

ArenaPushMark
:: (Arena: *arena)
{
  Arena.Mark = Arena.Used + 1;
}

ArenaPopMark
:: (Arena: *arena)
{
  Arena.Used = Arena.Mark - 1;
  Arena.Mark = 0;
}

ArenaReset
:: (Arena: *arena)
{
  Arena.Used = 0;
  Zero(Arena.Base, Arena.Committed);
}

DebugPrintArena
:: (Name: string, Arena: *arena)
{
  print("%: Reserved=%, Committed=%, Used=%\n", Name, Arena.Reserved, Arena.Committed, Arena.Used);
}

// NOTE(tt): arena arrays

ArrayAdd :: array_add;
ArrayRemove :: array_ordered_remove_by_index;
TableContains :: table_contains;
TableAdd :: table_add;

ArrayReset
:: (Array: *[..] $T)
{
  Array.count = 0;
}

CreateArenaArray
:: (Arena: *arena, $T: Type)
-> [..] T
{
  Result: [..] T;
  Result.allocator = CreateArenaAllocator(Arena);
  return Result;
}

CreateArenaTable
:: (Arena: *arena, $K: Type, $V: Type)
-> Table(K, V)
{
  Result: Table(K, V);
  Result.allocator = CreateArenaAllocator(Arena);
  return Result;
}

CreateArenaAllocator
:: (Arena: *arena)
-> Allocator
{
  ArenaAllocatorProc
  :: (Mode: Allocator_Mode, Size: s64, OldSize: s64, Old: *void, AllocatorData: *void)
  -> *void
  {
    Arena := cast(*arena) AllocatorData;
    if Mode ==
    {
      case .RESIZE;
        Result := ArenaAlloc(Arena, Size);
        memcpy(Result, Old, OldSize);
        return Result;
      case .ALLOCATE;
        return ArenaAlloc(Arena, Size);
    }
    return null;
  }
  return .{ArenaAllocatorProc, Arena};
}

// NOTE(tt): platform specific stuff

#if OS == .WINDOWS {
  using,only(
    VirtualAlloc,
    VirtualProtect,
    GetSystemInfo,
    MEM_RESERVE, MEM_COMMIT, PAGE_READONLY, PAGE_READWRITE,
    SYSTEM_INFO
  ) Windows :: #import "Windows";

  PlatformReserve
  :: (Size: int)
  -> *void
  {
    return VirtualAlloc(null, xx Size, MEM_RESERVE, PAGE_READWRITE);
  }

  PlatformCommit
  :: (Memory: *void, Size: int)
  {
    VirtualAlloc(Memory, xx Size, MEM_COMMIT, PAGE_READWRITE);
  }

  PlatformPageSize
  :: ()
  -> int
  {
    Info: SYSTEM_INFO;
    GetSystemInfo(*Info);
    return xx Info.dwPageSize;
  }
} else #if OS == .LINUX {
  using,only(
    mmap,
    getpagesize,
    mprotect,
    PROT_READ, PROT_WRITE, MAP_PRIVATE, MAP_ANONYMOUS, MAP_NORESERVE
  ) Linux :: #import "POSIX";

  PlatformReserve
  :: (Size: int)
  -> *void
  {
    return mmap(null, xx Size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, 0, 0);
  }

  PlatformCommit
  :: (Memory: *void, Size: int)
  {
  }

  PlatformPageSize
  :: ()
  -> int
  {
    return xx getpagesize();
  }
}

#import "Basic";
#import "Hash";
#import "Sort";
#import "Hash_Table";