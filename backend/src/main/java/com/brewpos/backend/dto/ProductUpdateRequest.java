package com.brewpos.backend.dto;

public class ProductUpdateRequest {
    private String name;
    private String section;
    private Integer sellPrice;
    private String imageUrl;

    public String getName() { return name; }
    public String getSection() { return section; }
    public Integer getSellPrice() { return sellPrice; }
    public String getImageUrl() { return imageUrl; }

    public void setName(String name) { this.name = name; }
    public void setSection(String section) { this.section = section; }
    public void setSellPrice(Integer sellPrice) { this.sellPrice = sellPrice; }
    public void setImageUrl(String imageUrl) { this.imageUrl = imageUrl; }
}