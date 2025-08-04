
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
Levels := string.[Level0, Level1];
HideLevel := false;

Level0 :: #string HERE
xxxxx
x x x
x xgx
x x x
x x x
x   x
x x x
x x x
xpxex
x x x
xxxxx
HERE

Level1 :: #string HERE
xxxxxxxxxxxxxxxxxxxx
x         x        x
x         x        x
x         x        x
x         x        x
x         x        x
x         x        x
x  p      d        x
x         x        x
x         x        x
x         x        x
x         x    e   x
x         x    g   x
xxxxxxxxxxxxxxxxxxxx
HERE

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

draw_text
:: struct
{
  Next: *draw_text;
  Font: *font;
  Position: vec2;
  String: string;
  Colour: vec4;
}

DrawText
:: (Font: *font, Position: vec2, String: string, Colour := vec4.{1, 1, 1, 1})
{
  Text := ArenaPushStruct(TextArena, draw_text);
  Text.Font = Font;
  Text.Position = Position;
  Text.String = String;
  Text.Colour = Colour;
  AddLinkedList(*FirstText, Text);
}

DrawTextOnTile
:: (Level: level, P: vec2i, Text: string, Colour := vec4.{1, 1, 1, 1})
{
  DrawText(DebugFont, ScreenPositionFromTilePosition(Level, P), Text, Colour);
}

DebugDrawText
:: (Text: string, Colour := vec4.{1, 1, 1, 1})
{
  DrawText(GameFont, DebugStringPosition, Text, Colour);
  DebugStringPosition.y += 16.0;
}

DrawAllText
:: ()
{
  Text := FirstText;
  while Text
  {
    Simp.draw_text(Text.Font, xx Text.Position.x, xx Text.Position.y, Text.String, Text.Colour);
    Text = Text.Next;
  }
  DebugStringPosition := vec2.{16, 16};

  FirstText = null;
  ArenaReset(TextArena);
}

draw_batch_kind
:: enum
{
  coloured_quad;
  textured_quad;
}

draw_batch_entry
:: struct
{
  Quad: quad;
  Colour: vec4;
}

draw_batch
:: struct
{
  Kind: draw_batch_kind;
  Entries: [..] draw_batch_entry;
  Texture: texture;
}

draw_batcher
:: struct
{
  Hash: [] int;
  Batches: [..] draw_batch;
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

InitDrawBatcher
:: (Arena: *arena, Batcher: *draw_batcher)
{
  Batcher.Hash = ArenaPushView(Arena, int, 1024);
  Batcher.Batches = CreateArenaArray(Arena, draw_batch);
}

DrawColouredQuad
:: (Arena: *arena, Batcher: *draw_batcher, Quad: quad, Colour: vec4)
{
  if Batcher.Hash.count == 0
  {
    InitDrawBatcher(Arena, Batcher);
  }
  if Batcher.Hash[0] == 0
  {
    Batcher.Hash[0] = 1;
    Batch: draw_batch;
    Batch.Kind = .coloured_quad;
    Batch.Entries = CreateArenaArray(Arena, draw_batch_entry);
    ArrayAdd(*Batcher.Batches, Batch);
  }
  Batch := *Batcher.Batches[0];
  ArrayAdd(*Batch.Entries, .{Quad, Colour});
}

DrawTexturedQuad
:: (Arena: *arena, Batcher: *draw_batcher, Quad: quad, Texture: *texture, Colour := vec4.{1, 1, 1, 1})
{
  if Batcher.Hash.count == 0
  {
    InitDrawBatcher(Arena, Batcher);
  }
  Hash := 1 + HashString(Texture.Path) % 1024;
  if Batcher.Hash[Hash] == 0
  {
    Batcher.Hash[Hash] = Batcher.Batches.count + 1;
    Batch: draw_batch;
    Batch.Kind = .textured_quad;
    Batch.Texture = Texture;
    ArrayAdd(*Batcher.Batches, Batch);
  }
  Index := Batcher.Hash[Hash] - 1;
  Batch := *Batcher.Batches[Index];
  ArrayAdd(*Batch.Entries, .{Quad, Colour});
}

BatchesSortFunction
:: (A: draw_batch, B: draw_batch)
-> int
{
  return cast(int) A.Kind - cast(int) B.Kind;
}

DrawBatches :: (Batcher: draw_batcher)
{
  QuickSort(Batcher.Batches, BatchesSortFunction);
  FirstRun := true;
  CurrentKind := draw_batch_kind.coloured_quad;
  CurrentTexture := "";
  for Batcher.Batches
  {
    ChangedState := FirstRun || it.Kind != CurrentKind;
    if it.Kind == .textured_quad
    {
      ChangedTexture := it.Texture.Path != CurrentTexture;
      if ChangedTexture
      {
        ChangedState = true;
        CurrentTexture = it.Texture.Path;
      }
    }
    if ChangedState
    {
      if it.Kind ==
      {
        case .coloured_quad;
          Simp.set_shader_for_color(true);
        case .textured_quad;
          Simp.set_shader_for_images(*it.Texture);
      }
      if !FirstRun
      {
        Simp.immediate_flush();
      }
      Simp.immediate_begin();
      FirstRun = false;
      CurrentKind = it.Kind;
    }
    for it.Entries
    {
      Simp.immediate_quad(it.Quad.Left, it.Quad.Top, it.Quad.Right, it.Quad.Bottom, it.Colour);
    }
  }
  Simp.immediate_flush();
}

entity_kind
:: enum
{
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
        Entity.Flags = .level_goal;
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

FindPathToTile
:: (Arena: *arena, Level: level, StartX: int, StartY: int, Goal: vec2i)
-> [] vec2i, bool
{
  Visited := ArenaPushView(Arena, bool, Level.Width * Level.Height);
  Parent := ArenaPushView(Arena, vec2i, Level.Width * Level.Height);
  Path := CreateArenaArray(Arena, vec2i);

  Queue := CreateArenaArray(Arena, vec2i);
  ArrayAdd(*Queue, .{StartX, StartY});

  W := Level.Width;
  Visited[StartX + StartY*W] = true;
  Parent[StartX + StartY*W] = .{-1, -1};

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
  :: (Level: level, P: vec2i)
  -> bool
  {
    Tile := GetTileAt(Level, P.x, P.y);
    Entity := GetEntityAt(Level, P.x, P.y);
    return !Tile.Blocking && !(Entity.Flags & .blocking);
  }

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
        if InBounds(Level, P) && IsWalkable(Level, P) && !Visited[P.x + P.y*W]
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

outcome_kind
:: enum
{
  movement;
  reached_goal;
  dead;
}

outcome
:: struct
{
  Kind: outcome_kind;
  Po: vec2i;
}

path_node
:: struct
{
  P: vec2i;
  Dir: movement_direction;
  From, To: vec2i;
}

tile_outcome
:: struct
{
  Outcomes: [..] outcome;
  P: vec2i;
  PathNodes: [] path_node;
  Reachable: bool;
}

FindLevelOutcomes
:: (Arena: *arena, Level: level)
-> [] tile_outcome
{
  TileOutcomes := ArenaPushView(Arena, tile_outcome, Level.Width * Level.Height);
  for y: 0..Level.Height-1
  {
    for x: 0..Level.Width-1
    {
      Path, Reachable := FindPathToTile(Arena, Level, Level.Player.Px, Level.Player.Py, .{x, y});
      TileOutcome := *TileOutcomes[x + y*Level.Width];
      TileOutcome.P = .{x, y};
      TileOutcome.Reachable = Reachable;
      if Reachable
      {
        TileOutcome.Outcomes = CreateArenaArray(Arena, outcome);

        PathNodes := ArenaPushView(Arena, path_node, Path.count);
        LastP := vec2i.{Level.Player.Px, Level.Player.Py};
        for Path
        {
          PathNodes[it_index].P = it;
          PathNodes[it_index].Dir = DirectionFromMove(.{LastP.x - it.x, LastP.y - it.y});
          PathNodes[it_index].From = it;
          PathNodes[it_index].To = LastP;
          LastP = it;
        }

        TileOutcome.PathNodes = PathNodes;
      }
    }
  }
  for y: 0..Level.Height-1
  {
    for x: 0..Level.Width-1
    {
      TileOutcome := *TileOutcomes[x + y*Level.Width];
      if TileOutcome.Reachable
      {
        Entity := GetEntityAt(Level, x, y);
        Outcome := outcome.{.movement, .{x, y}};
        if Entity != *StubEntity
        {
          if Entity.Flags & .causes_death
          {
            Outcome = outcome.{.dead, .{x, y}};
          }
          if Entity.Flags & .level_goal
          {
            Outcome = outcome.{.reached_goal, .{x, y}};
          }
        }
        for TileOutcome.PathNodes
        {
          TileOutcomeAtPoint := *TileOutcomes[it.P.x + it.P.y*Level.Width];
          ArrayAdd(*TileOutcomeAtPoint.Outcomes, Outcome);
        }
      }
    }
  }
  return TileOutcomes;
}

FindPossibleOutcome
:: (TileOutcome: tile_outcome, Kind: outcome_kind)
-> bool
{
  for TileOutcome.Outcomes
  {
    if it.Kind == Kind
    {
      return true;
    }
  }
  return false;
}

FindPossibleOutcomeFraction
:: (Level: level, TileOutcomes: [] tile_outcome, P: vec2i, Kind: outcome_kind)
-> float, float
{
  TileOutcome := *TileOutcomes[P.x + P.y*Level.Width];
  D := -1.0;
  if TileOutcome.Outcomes.count > 0
  {
    Count := 0.0;
    for TileOutcome.Outcomes
    {
      if it.Kind == Kind
      {
        Count += 1.0;
        if D < 0.0
        {
          // Pa := WorldPositionFromTilePosition(Level, );
          // Pb := WorldPositionFromTilePosition(Level, it.Po.x, it.Po.y);
          // D = Distance(Pa, Pb);
          D = Abs(cast(float) ((P.x - it.Po.x) + (P.y - it.Po.y)));
        }
      }
    }
    return Count / TileOutcome.Outcomes.count, D;
  }
  return 0.0, 9999.0;
}

tile_drawable_kind
:: enum
{
  tile;
  entity;
}

tile_drawable
:: struct
{
  Kind: tile_drawable_kind;
  P: vec2i;
  Texture: *texture;
  Colour: vec4;
  Layer: int;
}

GetTileDrawables
:: (Arena: *arena, Level: level)
-> [] tile_drawable
{
  PlayerP := vec2i.{Level.Player.Px, Level.Player.Py};

  drawable_layer_entity :: 0;
  drawable_layer_tile :: 1;

  Counts := ArenaPushView(Arena, int, Level.Width * Level.Height);
  Drawables := CreateArenaArray(Arena, tile_drawable);
  for Xa: 0..Level.Width-1 for Ya: 0..Level.Height-1
  {
    TileA := GetTileAt(Level, Xa, Ya);
    if TileA.Blocking continue;
    EntityA := GetEntityAt(Level, Xa, Ya);
    if EntityA.Flags & .blocking continue;

    Paths := vec2i.[
      .{PlayerP.x + -1, PlayerP.y +  0},
      .{PlayerP.x +  1, PlayerP.y +  0},
      .{PlayerP.x +  0, PlayerP.y + -1},
      .{PlayerP.x +  0, PlayerP.y +  1},
    ];
    for Paths
    {
      TileB := GetTileAt(Level, Xb, Yb);
      EntityB := GetEntityAt(Level, Xb, Yb);
      if TileB.Blocking continue;
      if EntityB.Flags & .blocking continue;
      if EntityB == *StubEntity continue;
      if EntityB.Kind == .player continue;

      Path, Reachable := FindPathToTile(Arena, Level, Xb, Yb, .{EntityB.Px, EntityB.Py});
      if !Reachable continue;

      LastP := vec2i.{Path[0].x, Path[0].y};
      for < Path
      {
        Dir := DirectionFromMove(.{it.x - LastP.x, it.y - LastP.y});
        LastP = it;

        Pa := WorldPositionFromTilePosition(Level, PlayerP);
        Pb := WorldPositionFromTilePosition(Level, .{it.y, it.y});
        D := Distance(Pa, Pb);
        MaxDistance := Max(Level.Width, Level.Height) * Level.TileSize * .5;
        if D >= MaxDistance continue;

        Alpha := 1.0 - (D / MaxDistance);

        if EntityB.Flags & .causes_death
        {
          Drawable: tile_drawable;
          Drawable.Kind = .entity;
          Drawable.P = .{it.x, it.y};
          Drawable.Texture = SkullTexture;
          Drawable.Colour = .{1, 1, 1, Alpha};
          Drawable.Layer = drawable_layer_entity;
          ArrayAdd(*Drawables, Drawable);
          Counts[it.x + it.y*Level.Width] += 1;
          DrawTextOnTile(Level, .{it.x, it.y}, TempString("%", FormatFloat.{value = Alpha, trailing_width = 1}), .{0, 1, 0, 1});
        }
      }
    }
  }
  for * Drawables
  {
    Count := Counts[it.P.x + it.P.y*Level.Width];
    if it.Kind == .tile
    {
      it.Colour.w /= Count;
    }
  }
  DrawablesSortFunction
  :: (A: tile_drawable, B: tile_drawable)
  -> int
  {
    return cast(int) B.Layer - cast(int) A.Layer;
  }
  QuickSort(Drawables, DrawablesSortFunction);
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
                HandleUseKey(CurrentLevel);

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
      LevelIndex = (LevelIndex + 1) % Levels.count;
      CurrentLevel = LoadLevel(Arena, Levels[LevelIndex]);
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

HandleUseKey
:: (Level: level)
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
      if Entity.Kind == .door
      {
        Entity.Flags |= .hidden;
        Entity.Flags &= ~.blocking;
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

WindowCreation :: #import "Window_Creation";
Simp :: #import "Simp";
Input :: #import "Input";
#import "Basic";
#import "Math";