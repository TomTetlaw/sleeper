
// NOTE(tt): quad drawing

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

// NOTE(tt): text drawing

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