const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Expansion = struct {
    allocator: Allocator,
    items: [][]u8,

    pub fn deinit(self: *Expansion) void {
        for (self.items) |item| self.allocator.free(item);
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

const Group = struct {
    open: usize,
    close: usize,
};

/// Expand comma-bearing brace alternatives while leaving globlike regex
/// excerpts opaque. The caller owns every returned string and the outer slice.
pub fn expand(allocator: Allocator, source: []const u8) Allocator.Error!Expansion {
    var items: std.ArrayListUnmanaged([]u8) = .empty;
    errdefer {
        for (items.items) |item| allocator.free(item);
        items.deinit(allocator);
    }

    if (std.mem.startsWith(u8, source, "regex:")) {
        const copy = try allocator.dupe(u8, source);
        errdefer allocator.free(copy);
        try items.append(allocator, copy);
    } else {
        try expandInto(allocator, source, &items);
    }

    return .{
        .allocator = allocator,
        .items = try items.toOwnedSlice(allocator),
    };
}

fn expandInto(
    allocator: Allocator,
    source: []const u8,
    output: *std.ArrayListUnmanaged([]u8),
) Allocator.Error!void {
    const group = findExpandableGroup(source) orelse {
        const copy = try allocator.dupe(u8, source);
        errdefer allocator.free(copy);
        try output.append(allocator, copy);
        return;
    };

    var alternative_start = group.open + 1;
    var index = alternative_start;
    var nested_depth: usize = 0;
    while (index <= group.close) {
        if (index < group.close and startsRegexExcerpt(source, index)) {
            index = skipRegexExcerpt(source, index);
            continue;
        }

        const at_separator = index == group.close or
            (source[index] == ',' and nested_depth == 0);
        if (at_separator) {
            const alternative = source[alternative_start..index];
            const combined_len = group.open + alternative.len + source.len - group.close - 1;
            const combined = try allocator.alloc(u8, combined_len);
            defer allocator.free(combined);

            var destination: usize = 0;
            @memcpy(combined[destination .. destination + group.open], source[0..group.open]);
            destination += group.open;
            @memcpy(combined[destination .. destination + alternative.len], alternative);
            destination += alternative.len;
            const suffix = source[group.close + 1 ..];
            @memcpy(combined[destination .. destination + suffix.len], suffix);

            try expandInto(allocator, combined, output);
            alternative_start = index + 1;
        } else switch (source[index]) {
            '{' => nested_depth += 1,
            '}' => if (nested_depth > 0) {
                nested_depth -= 1;
            },
            else => {},
        }
        index += 1;
    }
}

fn findExpandableGroup(source: []const u8) ?Group {
    var index: usize = 0;
    while (index < source.len) {
        if (startsRegexExcerpt(source, index)) {
            index = skipRegexExcerpt(source, index);
            continue;
        }
        if (source[index] != '{') {
            index += 1;
            continue;
        }

        const close = findMatchingBrace(source, index) orelse {
            index += 1;
            continue;
        };
        if (containsTopLevelComma(source, index + 1, close)) {
            return .{ .open = index, .close = close };
        }

        // The outer pair may be literal while a nested pair is expandable.
        index += 1;
    }
    return null;
}

fn findMatchingBrace(source: []const u8, open: usize) ?usize {
    var depth: usize = 1;
    var index = open + 1;
    while (index < source.len) {
        if (startsRegexExcerpt(source, index)) {
            index = skipRegexExcerpt(source, index);
            continue;
        }
        switch (source[index]) {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if (depth == 0) return index;
            },
            else => {},
        }
        index += 1;
    }
    return null;
}

fn containsTopLevelComma(source: []const u8, start: usize, end: usize) bool {
    var depth: usize = 0;
    var index = start;
    while (index < end) {
        if (startsRegexExcerpt(source, index)) {
            index = skipRegexExcerpt(source, index);
            continue;
        }
        switch (source[index]) {
            '{' => depth += 1,
            '}' => if (depth > 0) {
                depth -= 1;
            },
            ',' => if (depth == 0) return true,
            else => {},
        }
        index += 1;
    }
    return false;
}

fn startsRegexExcerpt(source: []const u8, index: usize) bool {
    return index + 3 <= source.len and std.mem.eql(u8, source[index .. index + 3], "%r{");
}

fn skipRegexExcerpt(source: []const u8, start: usize) usize {
    var depth: usize = 1;
    var index = start + 3;
    while (index < source.len) {
        if (source[index] == '\\' and index + 1 < source.len) {
            index += 2;
            continue;
        }
        switch (source[index]) {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                index += 1;
                if (depth == 0) return index;
                continue;
            },
            else => {},
        }
        index += 1;
    }
    return source.len;
}

fn expectExpansion(source: []const u8, expected: []const []const u8) !void {
    var result = try expand(std.testing.allocator, source);
    defer result.deinit();
    try std.testing.expectEqual(expected.len, result.items.len);
    for (expected, result.items) |want, actual| {
        try std.testing.expectEqualStrings(want, actual);
    }
}

test "simple alternatives" {
    try expectExpansion("*.{jpg,png}", &.{ "*.jpg", "*.png" });
}

test "adjacent alternatives retain Bash ordering" {
    try expectExpansion("file{1,2}.{jpg,png}", &.{
        "file1.jpg",
        "file1.png",
        "file2.jpg",
        "file2.png",
    });
}

test "nested alternatives recurse" {
    try expectExpansion("{a,{b,c}}.txt", &.{ "a.txt", "b.txt", "c.txt" });
}

test "spaces and extglob text are preserved" {
    try expectExpansion("dir with spaces/@(*.{jpg,png}|x)", &.{
        "dir with spaces/@(*.jpg|x)",
        "dir with spaces/@(*.png|x)",
    });
}

test "regex excerpt braces and commas are opaque" {
    try expectExpansion("file{a,b}-%r{[0-9]{2,4}}.txt", &.{
        "filea-%r{[0-9]{2,4}}.txt",
        "fileb-%r{[0-9]{2,4}}.txt",
    });
    try expectExpansion("%r{foo,bar}", &.{"%r{foo,bar}"});
}

test "full regex mode is opaque" {
    try expectExpansion("regex:^(foo|bar){2,4}$", &.{"regex:^(foo|bar){2,4}$"});
}

test "ordinary unmatched and comma-free braces stay literal" {
    try expectExpansion("literal{brace}", &.{"literal{brace}"});
    try expectExpansion("literal{open", &.{"literal{open"});
}
