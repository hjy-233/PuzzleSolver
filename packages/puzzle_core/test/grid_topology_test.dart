import 'package:puzzle_core/puzzle_core.dart';
import 'package:test/test.dart';

void main() {
  group('GridTopology', () {
    const topology = GridTopology(rows: 2, columns: 3);

    test('a neighbouring pair of cells shares exactly one canonical edge', () {
      const left = CellId(0, 0);
      const right = CellId(0, 1);

      expect(topology.edgesAround(left), contains(const EdgeId.vertical(0, 1)));
      expect(
        topology.edgesAround(right),
        contains(const EdgeId.vertical(0, 1)),
      );
      expect(topology.cellsBeside(const EdgeId.vertical(0, 1)), [left, right]);
    });

    test('keeps horizontal and vertical edge bounds distinct', () {
      expect(topology.containsEdge(const EdgeId.horizontal(2, 2)), isTrue);
      expect(topology.containsEdge(const EdgeId.horizontal(2, 3)), isFalse);
      expect(topology.containsEdge(const EdgeId.vertical(2, 3)), isFalse);
      expect(topology.containsEdge(const EdgeId.vertical(1, 3)), isTrue);
    });
  });
}
