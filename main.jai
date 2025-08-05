
GameTime: float;

font :: Simp.Dynamic_Font;

GameFont: *font;
DebugFont: *font;

PlayerForwardTexture: *texture;
PlayerBackwardTexture: *texture;
PlayerLeftTexture: *texture;
PlayerRightTexture: *texture;
EnemyTexture: *texture;
SkullTexture: *texture;
GoalTexture: *texture;

WindowWidth := 1366;
WindowHeight := 768;

FrameArena: *arena;
AssetArena: *arena;
GameArena: *arena;

DebugStringPosition := vec2.{16, 16};
FirstText: *draw_text;
TextArena: *arena;

CurrentLevel: level;

PlayerDirection: movement_direction;

LevelIndex := 0;
HideLevel := false;

Level0 :: #string HERE
xxxxxxxxxxxxxxxxxxxxxxxxx
x p                     x
xxxxxxxxxxx   xxxxx  xxxx
x    g          e       x
xxxxxxxxxxxxxxxxxxxxxxxxx
HERE

Level1 :: #string HERE
xxxxxxxxxxxxxxxxxxxxxxxxx
x p                     x
xxxxxxxxxxxxx xxxxxx xxxx
x            e  g       x
xxxxxxxxxxxxxxxxxxxxxxxxx
HERE

Level2 :: #string HERE
xxxxxxxxxxxxxxxxxxxxxxxxx
x p                     x
xxxxxxxxxxxxxxxxxxdxxxxxx
x    g                  x
xxxxxxxxxxxxxxxxxxxxxxxxx
HERE

Levels := string.[Level0, Level1, Level2];

PlayerTextureFromDirection
:: (Dir: movement_direction)
-> *texture
{
  if Dir ==
  {
    case .none;
      #through;
    case .up;
      return PlayerForwardTexture;
    case .down;
      return PlayerBackwardTexture;
    case .left;
      return PlayerLeftTexture;
    case .right;
      return PlayerRightTexture;
  }
  return null;
}

texture
:: struct
{
  Path: string;
  using #as Texture: Simp.Texture;
}

LoadTexture
:: (Arena: *arena, Path: string)
-> *texture
{
  Result := ArenaPushStruct(Arena, texture);
  Result.Path = ArenaPushString(Arena, Path);
  Simp.texture_load_from_file(*Result.Texture, Path);
  return Result;
}

entity_kind
:: enum
{
  stub;
  player;
  enemy;
  goal;
  door;
}

entity_flags
:: enum_flags
{
  blocking;
  causes_death;
  level_goal;
  hidden;
  interactable;
}

entity
:: struct
{
  Kind: entity_kind;
  Px, Py: int;
  Colour: Vector4;
  Dead: bool;
  Flags: entity_flags;
  Mx, My: int;
}
StubEntity :: entity.{};

tile_kind
:: enum
{
  floor;
  wall;
}

tile
:: struct
{
  Kind := tile_kind.floor;
  Px, Py: int;
  Blocking: bool;
}
StubTile :: tile.{};

level
:: struct
{
  Width, Height: int;
  TileSize: float;
  Player: *entity;
  Enemy: *entity;
  Entities: [..] entity;
  Tiles: [] tile;
}

LoadLevel
:: (Arena: *arena, LevelString: string)
-> level
{
  X, Y: int;
  Width, Height: int;
  for LevelString
  {
    if it == #char "\n"
    {
      Height += 1;
      Y += 1;
      X = 0;
    }
    else
    {
      X += 1;
    }
    Width = max(Width, X);
  }

  Result: level;
  Result.Width = Width;
  Result.Height = Height;
  Result.TileSize = 32;
  Result.Tiles = ArenaPushView(Arena, tile, Result.Width * Result.Height);
  Result.Entities = CreateArenaArray(Arena, entity);

  X = 0;
  Y = 0;
  for LevelString
  {
    if it != #char "\n"
    {
      Result.Tiles[X + Y * Width].Px = X;
      Result.Tiles[X + Y * Width].Py = Y;
    }
    if it ==
    {
      case #char "\n";
      {
        Y += 1;
        X = 0;
      }
      case #char " ";
        Result.Tiles[X + Y * Width].Kind = .floor;
        X += 1;
      case #char "x";
        Result.Tiles[X + Y * Width].Kind = .wall;
        Result.Tiles[X + Y * Width].Blocking = true;
        X += 1;
      case #char "p";
        Entity: entity;
        Entity.Kind = .player;
        Entity.Px = X;
        Entity.Py = Y;
        ArrayAdd(*Result.Entities, Entity);
        X += 1;
      case #char "e";
        Entity: entity;
        Entity.Kind = .enemy;
        Entity.Flags = .causes_death;
        Entity.Px = X;
        Entity.Py = Y;
        Entity.Mx = -1;
        ArrayAdd(*Result.Entities, Entity);
        X += 1;
      case #char "g";
        Entity: entity;
        Entity.Kind = .goal;
        Entity.Flags = .level_goal | .blocking | .interactable;
        Entity.Px = X;
        Entity.Py = Y;
        ArrayAdd(*Result.Entities, Entity);
        X += 1;
      case #char "d";
        Entity: entity;
        Entity.Kind = .door;
        Entity.Flags = .blocking | .interactable;
        Entity.Px = X;
        Entity.Py = Y;
        ArrayAdd(*Result.Entities, Entity);
        X += 1;
    }
  }
  Result.Player = FindEntity(Result, .player);
  Result.Enemy = FindEntity(Result, .enemy);
  return Result;
}

FindEntity
:: (Level: level, Kind: entity_kind)
-> *entity
{
  for * Level.Entities
  {
    if it.Kind == Kind
    {
      return it;
    }
  }
  return null;
}

state_outcome
:: enum
{
  goal;
  death;
  ongoing;
}

dag_node
:: struct
{
  Next: *dag_node;
  Hash: u32;
  Depth: int;
  Outcome: state_outcome;
  Children: [] *dag_node;
  Entities: [] entity;
}

node_action_kind
:: enum
{
  move;
  interact;
}

node_action
:: struct
{
  Kind: node_action_kind;
  Actor: *entity; // NOTE(tt): the entity that is doing the action
  Target: *entity; // NOTE(tt): the entity that the action is happening to
}

BuildGraph
:: (Arena: *arena, InitialState: level)
-> [] *dag_node
{
  max_depth :: 15;

  FirstNode: *dag_node;
  Queue := CreateArenaArray(Arena, *dag_node);
  NodeHash := CreateArenaTable(Arena, u32, *dag_node);



  while Queue.count > 0
  {
    Node := Queue[0];
    ArrayRemove(*Queue, 0);
    if Node.Depth < max_depth
    {
      Node.Hash = HashNode(Node);
      if !TableContains(*Visited, Node.Hash)
      {
        TableAdd(*NodeHash, Node.Hash, Node);
        if IsOngoing(Node)
        {
          Actions := NodeActions(Node);
          for Actions
          {
            Next := StepNode(Node, it);
            NextHash := HashNode(Next);
            ArrayAdd(*Node.Children, Next);
            ArrayAdd(*Queue, Next);
          }
        }
      }
    }
  }
}

tile_drawable
:: struct
{
  P: vec2i;
  Texture: *texture;
  Colour: vec4;
}

GetTileDrawables
:: (Arena: *arena, Level: level)
-> [] tile_drawable
{
  Drawables := CreateArenaArray(Arena, tile_drawable);
  return Drawables;
}

main
:: ()
{
  Window := WindowCreation.create_window(WindowWidth, WindowHeight, "Sleeper");
  Simp.prepare_window(Window, 0);
  Simp.set_render_target(Window, .LEFT_HANDED);
  WindowWidth, WindowHeight = Simp.get_render_dimensions(Window);

  FrameArena = CreateArena();
  AssetArena = CreateArena();
  GameArena = CreateArena();
  TextArena = CreateArena();

  GameFont = Simp.get_font_at_size("Fonts", "OpenSans-BoldItalic.ttf", 16);
  DebugFont = Simp.get_font_at_size("Fonts", "OpenSans-BoldItalic.ttf", 12);

  PlayerForwardTexture = LoadTexture(AssetArena, "Textures/PlayerForward.png");
  PlayerBackwardTexture = LoadTexture(AssetArena, "Textures/PlayerBackward.png");
  PlayerLeftTexture = LoadTexture(AssetArena, "Textures/PlayerLeft.png");
  PlayerRightTexture = LoadTexture(AssetArena, "Textures/PlayerRight.png");
  EnemyTexture = LoadTexture(AssetArena, "Textures/Enemy.png");
  SkullTexture = LoadTexture(AssetArena, "Textures/Skull.png");
  GoalTexture = LoadTexture(AssetArena, "Textures/Goal.png");

  CurrentLevel = LoadLevel(GameArena, Level0);

  Quit := false;
  while !Quit
  {
    GameTime = xx seconds_since_init();

    Input.update_window_events();
    for Input.get_window_resizes()
    {
      Simp.update_window(it.window);
      if it.window == Window
      {
        WindowWidth = it.width;
        WindowHeight = it.height;
      }
    }
    for Input.events_this_frame
    {
      if it.type ==
      {
        case .QUIT;
          Quit = true;
        case .KEYBOARD;
        {
          if it.key_pressed
          {
            if it.key_code ==
            {
              case .ESCAPE;
                Quit = true;

              case #char "W";
                TryMoveEntity(GameArena, *CurrentLevel, CurrentLevel.Player,  0, -1);
                PlayerDirection = .up;
              case #char "A";
                TryMoveEntity(GameArena, *CurrentLevel, CurrentLevel.Player, -1,  0);
                PlayerDirection = .left;
              case #char "S";
                TryMoveEntity(GameArena, *CurrentLevel, CurrentLevel.Player,  0,  1);
                PlayerDirection = .down;
              case #char "D";
                TryMoveEntity(GameArena, *CurrentLevel, CurrentLevel.Player,  1,  0);
                PlayerDirection = .right;
              case #char "E";
                HandleUseKey(GameArena, CurrentLevel);

              case .ARROW_UP;
                TryMoveEntity(GameArena, *CurrentLevel, CurrentLevel.Enemy,  0, -1);
              case .ARROW_LEFT;
                TryMoveEntity(GameArena, *CurrentLevel, CurrentLevel.Enemy, -1,  0);
              case .ARROW_DOWN;
                TryMoveEntity(GameArena, *CurrentLevel, CurrentLevel.Enemy,  0,  1);
              case .ARROW_RIGHT;
                TryMoveEntity(GameArena, *CurrentLevel, CurrentLevel.Enemy,  1,  0);

              case .F1;
                HideLevel = !HideLevel;
            }
          }
        }
      }
    }

    Simp.clear_render_target(.08, .08, .08, 1);
    DrawBatcher := ArenaPushStruct(FrameArena, draw_batcher);
    if !HideLevel
    {
      DrawLevel(FrameArena, DrawBatcher, CurrentLevel);
    }

    Drawables := GetTileDrawables(FrameArena, CurrentLevel);
    for Drawables
    {
      Ps := ScreenPositionFromTilePosition(CurrentLevel, it.P);
      Quad := QuadFromScreenPosition(CurrentLevel, Ps);
      DrawTexturedQuad(FrameArena, DrawBatcher, Quad, it.Texture, it.Colour);
    }

    DrawBatches(DrawBatcher);
    DrawAllText();

    Simp.swap_buffers(Window);

    ArenaReset(FrameArena);
  }
}

CanMoveEntity
:: (Level: level, Entity: *entity, Mx: int, My: int)
-> bool
{
  if Entity.Dead
  {
    return false;
  }
  Tx := Entity.Px + Mx;
  Ty := Entity.Py + My;
  Tile := GetTileAt(Level, Tx, Ty);
  if Tile.Blocking
  {
    return false;
  }
  else
  {
    EntityAtTarget := GetEntityAt(Level, Tx, Ty);
    if EntityAtTarget.Flags & .blocking
    {
      return false;
    }
    return true;
  }
}

HandleEntityInteraction
:: (Arena: *arena, Level: level, Entity: *entity, Other: *entity)
-> bool
{
  Player: *entity;
  if Entity.Kind == .player
  {
    Player = Entity;
  }
  else if Other.Kind == .player
  {
    Player = Other;
    Other = Entity;
  }
  if Player
  {
    if Other.Kind == .goal
    {
      LoadNextLevel(Arena);
    }
  }
  return true;
}

TryMoveEntity
:: (Arena: *arena, Level: level, Entity: *entity, Mx: int, My: int)
-> bool
{
  if CanMoveEntity(Level, Entity, Mx, My)
  {
    DoMove := true;
    Tx := Entity.Px + Mx;
    Ty := Entity.Py + My;
    Other := GetEntityAt(Level, Tx, Ty);
    if Other != Entity
    {
      DoMove = HandleEntityInteraction(Arena, Level, Entity, Other);
    }
    if DoMove
    {
      Entity.Px += Mx;
      Entity.Py += My;
    }
    return true;
  }
  return false;
}

GetEntityAt
:: (Level: level, Px: int, Py: int)
-> *entity
{
  if Px >= 0 && Px < Level.Width
  {
    if Py >= 0 && Py < Level.Height
    {
      for * Level.Entities
      {
        if it.Px == Px && it.Py == Py
        {
          return it;
        }
      }
    }
  }
  return *StubEntity;
}

GetTileAt
:: (Level: level, Px: int, Py: int)
-> *tile
{
  if Px >= 0 && Px < Level.Width
  {
    if Py >= 0 && Py < Level.Height
    {
      return *Level.Tiles[Px + Py * Level.Width];
    }
  }
  return *StubTile;
}

DrawEntity
:: (Arena: *arena, Batcher: *draw_batcher, Level: level, Entity: entity)
{
  P := ScreenPositionFromTilePosition(Level, .{Entity.Px, Entity.Py});
  Quad := QuadFromScreenPosition(Level, P);
  if !(Entity.Flags & .hidden)
  {
    if Entity.Dead
    {
      DrawTexturedQuad(Arena, Batcher, Quad, SkullTexture);
    }
    else
    {
      if Entity.Kind ==
      {
        case .player;
          PlayerTexture := PlayerTextureFromDirection(PlayerDirection);
          DrawTexturedQuad(Arena, Batcher, Quad, PlayerTexture);
        case .enemy;
          DrawTexturedQuad(Arena, Batcher, Quad, EnemyTexture);
        case .goal;
          DrawColouredQuad(Arena, Batcher, Quad, .{0, 1, 0, 1});
        case .door;
          DrawColouredQuad(Arena, Batcher, Quad, .{1, 1, 1, 1});
      }
    }
  }
}

DrawLevel
:: (Arena: *arena, Batcher: *draw_batcher, Level: level)
{
  for * Level.Tiles
  {
    P := ScreenPositionFromTilePosition(Level, .{it.Px, it.Py});
    Quad := QuadFromScreenPosition(Level, P);
    if it.Kind ==
    {
      case .wall;
        DrawColouredQuad(Arena, Batcher, Quad, .{1, 0, 0, 1});
      case .floor;
        DrawColouredQuad(Arena, Batcher, Quad, .{0, 0, 0, 1});
    }
  }
  for Level.Entities
  {
    DrawEntity(Arena, Batcher, Level, it);
  }
}

LoadNextLevel
:: (Arena: *arena)
{
  LevelIndex = (LevelIndex + 1) % Levels.count;
  CurrentLevel = LoadLevel(Arena, Levels[LevelIndex]);
}

HandleUseKey
:: (Arena: *arena, Level: level)
{
  Dirs := vec2i.[
    .{1, 0},
    .{0, -1},
    .{-1, 0},
    .{0, 1},
    .{-1, 1},
    .{-1, -1},
    .{1, -1},
    .{1, 1},
  ];

  for Dirs
  {
    P := vec2i.{Level.Player.Px + it.x, Level.Player.Py + it.y};
    Entity := GetEntityAt(Level, P.x, P.y);
    if Entity.Flags & .interactable
    {
      if Entity.Kind ==
      {
        case .door;
          Entity.Flags |= .hidden;
          Entity.Flags &= ~.blocking;
        case .goal;
          LoadNextLevel(Arena);
      }
    }
  }
}

movement_direction
:: enum
{
  none;
  left;
  right;
  up;
  down;
}

DirectionFromMove
:: (M: vec2i)
-> movement_direction
{
  if M.x ==
  {
    case -1;
      return .left;
    case 1;
      return .right;
  }

  if M.y ==
  {
    case -1;
      return .up;
    case 1;
      return .down;
  }

  return .none;
}

ScreenPositionFromTilePosition
:: (Level: level, P: vec2i)
-> vec2
{
  return vec2.{
    (P.x - Level.Player.Px)*Level.TileSize + WindowWidth*.5,
    (P.y - Level.Player.Py)*Level.TileSize + WindowHeight*.5
  };
}

WorldPositionFromTilePosition
:: (Level: level, P: vec2i)
-> vec2
{
  return vec2.{P.x * Level.TileSize, P.y * Level.TileSize};
}

QuadFromScreenPosition
:: (Level: level, P: vec2)
-> quad
{
  Left := P.x - Level.TileSize*.5;
  Top := P.y - Level.TileSize*.5;
  Right := P.x + Level.TileSize*.5;
  Bottom := P.y + Level.TileSize*.5;
  return .{Left, Top, Right, Bottom};
}

TempString
:: (Format: string, Args: ..Any)
-> string
{
  Builder: String_Builder;
  Builder.allocator = CreateArenaAllocator(FrameArena);
  print_to_builder(*Builder, Format, ..Args);
  Message := builder_to_string(*Builder);
  return Message;
}

#load "base.jai";
#load "draw.jai";

WindowCreation :: #import "Window_Creation";
Simp :: #import "Simp";
Input :: #import "Input";
#import "Basic";
#import "Math";

/*

InBounds
:: (Level: level, P: vec2i)
-> bool
{
  InsideLeft := P.x >= 0;
  InsideRight := P.x < Level.Width;
  InsideTop := P.y >= 0;
  InsideBottom := P.y < Level.Height;
  return InsideLeft && InsideRight && InsideTop && InsideBottom;
}

IsWalkable
:: (Level: level, P: vec2i, Goal: vec2i)
-> bool
{
  Tile := GetTileAt(Level, P.x, P.y);
  Entity := GetEntityAt(Level, P.x, P.y);

  if Tile.Blocking return false;

  GoalEntity := GetEntityAt(Level, Goal.x, Goal.y);
  if GoalEntity.Kind == .goal
  {
    if GoalEntity.Flags & .interactable return true;
  }

  if Entity.Flags & .blocking return false;

  return true;
}

pathfinding_state
:: struct
{
  Visited: [] bool;
  Path: [..] vec2i;
  AllPaths: [..] [] vec2i;
}

FindPathRecursive
:: (Arena: *arena, State: *pathfinding_state, Level: level, P: vec2i, Goal: vec2i, Depth := 0)
{
  MaxDepth := 5000;//Max(Level.Width, Level.Height);
  if Depth >= MaxDepth
  {
    return;
  }
  if !InBounds(Level, P)
  {
    return;
  }
  if State.Visited[P.x + P.y*Level.Width]
  {
    return;
  }
  if !IsWalkable(Level, P, Goal)
  {
    return;
  }

  ArrayAdd(*State.Path, P);
  State.Visited[P.x + P.y*Level.Width] = true;

  if P.x == Goal.x && P.y == Goal.y
  {
    Path := ArenaPushView(Arena, vec2i, State.Path.count);
    for * Path it.* = State.Path[it_index];
    ArrayAdd(*State.AllPaths, Path);
  }
  else
  {
    FindPathRecursive(Arena, State, Level, .{P.x + 1, P.y}, Goal, Depth + 1);
    FindPathRecursive(Arena, State, Level, .{P.x - 1, P.y}, Goal, Depth + 1);
    FindPathRecursive(Arena, State, Level, .{P.x, P.y + 1}, Goal, Depth + 1);
    FindPathRecursive(Arena, State, Level, .{P.x, P.y - 1}, Goal, Depth + 1);
  }

  State.Visited[P.x + P.y*Level.Width] = false;
  State.Path.count -= 1;
}

FindAllPathsToTile
:: (Arena: *arena, Level: level, Start: vec2i, Goal: vec2i)
-> [] [] vec2i
{
  State := ArenaPushStruct(Arena, pathfinding_state);
  State.Visited = ArenaPushView(Arena, bool, Level.Width * Level.Height);
  State.Path = CreateArenaArray(Arena, vec2i);
  State.AllPaths = CreateArenaArray(Arena, [] vec2i);
  FindPathRecursive(Arena, State, Level, Start, Goal);
  return State.AllPaths;
}

FindShortestPathToTile
:: (Arena: *arena, Level: level, Start: vec2i, Goal: vec2i)
-> [] vec2i, bool
{
  Visited := ArenaPushView(Arena, bool, Level.Width * Level.Height);
  Parent := ArenaPushView(Arena, vec2i, Level.Width * Level.Height);
  Path := CreateArenaArray(Arena, vec2i);

  Queue := CreateArenaArray(Arena, vec2i);
  ArrayAdd(*Queue, Start);

  W := Level.Width;
  Visited[Start.x + Start.y*W] = true;
  Parent[Start.x + Start.y*W] = .{-1, -1};

  while Queue.count > 0
  {
    Current := Queue[0];
    ArrayRemove(*Queue, 0);
    if Current.x == Goal.x && Current.y == Goal.y
    {
      P := Goal;
      while P.x != -1 && P.y != -1
      {
        ArrayAdd(*Path, P);
        P = Parent[P.x + P.y*W];
      }
      break;
    }
    else
    {
      Dirs := vec2i.[
        .{1, 0},
        .{0, -1},
        .{-1, 0},
        .{0, 1},
      ];
      for Dirs
      {
        P := vec2i.{Current.x + it.x, Current.y + it.y};
        if InBounds(Level, P) && IsWalkable(Level, P, Goal) && !Visited[P.x + P.y*W]
        {
          Visited[P.x + P.y*W] = true;
          Parent[P.x + P.y*W] = Current;
          ArrayAdd(*Queue, P);
        }
      }
    }
  }

  return Path, Path.count > 0;
}
*/