package com.mypagerank;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class Graph {
    private Map<String, Node> nodes = new HashMap<>();

    public void addNode(String name) {
        nodes.putIfAbsent(name, new Node(name));
    }

    public Node getNode(String name) {
        return nodes.get(name);
    }

    public void addEdge(String from, String to) {
        addNode(from);
        addNode(to);
        getNode(from).addOutgoingEdge(getNode(to));
    }

    public List<Node> getAllNodes() {
        return new ArrayList<>(nodes.values());
    }

    public int getNumNodes() {
        return nodes.size();
    }
}